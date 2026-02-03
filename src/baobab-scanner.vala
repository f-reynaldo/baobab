/* -*- tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*- */
/* Baobab - disk usage analyzer
 *
 * Copyright (C) 2012  Ryan Lortie <desrt@desrt.ca>
 * Copyright (C) 2012  Paolo Borelli <pborelli@gnome.org>
 * Copyright (C) 2012  Stefano Facchini <stefano.facchini@gmail.com>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

using Posix;

namespace Baobab {

    [Flags]
    public enum ScanFlags {
        NONE,
        EXCLUDE_MOUNTS
    }

    public class Scanner : Object {
        public enum State {
            SCANNING,
            ERROR,
            CHILD_ERROR,
            DONE
        }

        public Results root { get; set; }

        public File? directory { get; private set; }

        public ScanFlags scan_flags { get; private set; }

        public bool show_allocated_size { get; private set; }

        // Used for progress reporting, should be updated whenever a new Results object is created
        public uint64 total_size { get; private set; }
        public int total_elements { get; private set; }

        public int max_depth { get; protected set; }

        public signal void completed();

        public File get_file (Results results) {
            List<string> names = null;

            for (Results? child = results; child != null; child = child.parent) {
                names.prepend (child.name);
            }

            var file = directory;
            foreach (var name in names.next) {
                file = file.get_child (name);
            }

            return file;
        }

        const string ATTRIBUTES =
            FileAttribute.STANDARD_NAME + "," +
            FileAttribute.STANDARD_DISPLAY_NAME + "," +
            FileAttribute.STANDARD_TYPE + "," +
            FileAttribute.STANDARD_SIZE +  "," +
            FileAttribute.STANDARD_ALLOCATED_SIZE + "," +
            FileAttribute.TIME_MODIFIED + "," +
            FileAttribute.UNIX_NLINK + "," +
            FileAttribute.UNIX_INODE + "," +
            FileAttribute.UNIX_DEVICE;


        Thread<void*>? thread = null;
        uint process_result_idle = 0;

        GenericSet<string> excluded_locations;

        bool successful = false;

        /* General overview:
         *
         * We cannot directly modify the model from the worker thread, so we have to have a way to dispatch
         * the results back to the main thread.
         *
         * Each scanned directory gets a 'Results' object created for it.  If the directory has a parent
         * directory, then the 'parent' pointer is set.  The 'display_name' and 'name' fields are filled
         * in as soon as the object is created.  This part is done as soon as the directory is encountered.
         *
         * In order to determine all of the information for a particular directory (and finish filling in the
         * results object), we must scan it and all of its children.  We must also scan all of the siblings
         * of the directory so that we know what percentage of the total size of the parent directory the
         * directory in question is responsible for.
         *
         * After a directory, all of its children and all of its siblings have been scanned, we can do the
         * percentage calculation.  We do this from the iteration that takes care of the parent directory: we
         * collect an array of all of the child directory result objects and when we have them all, we assign
         * the proper percentage to each.  At this point we can report this array of result objects back to the
         * main thread to be added to the model.
         *
         * Back in the main thread, we receive a Results object.  We add the object to its parent's children
         * list, we fill in the data that existed from the start (ie: display name and name).
         *
         * We can be sure that the 'parent' field always points to valid memory because of the nature of the
         * recursion and the queue.  At the time we queue a Results object for dispatch back to the main thread,
         * its 'parent' is held on the stack by a higher invocation of add_directory().  This invocation will
         * never finish without first pushing its own Results object onto the queue -- after ours.  It is
         * therefore guaranteed that the 'parent' Results object will not be freed before each child.
         */

        AsyncQueue<ResultsArray> results_queue;
        Scanner? self;
        Cancellable cancellable;
        Error? scan_error;

        [Compact]
        class ResultsArray {
            internal Results[] results;
        }

        public class Results : Object {
            // written in the worker thread on creation
            // read from the main thread at any time
            public unowned Results? parent { get; internal set; }
            public string name { get; internal set; }
            public string display_name { get; internal set; }
            internal FileType file_type;

            // written in the worker thread before dispatch
            // read from the main thread only after dispatch
            public uint64 size { get; internal set; }
            public uint64 pid { get; internal set; }
            public uint64 time_modified { get; internal set; }
            public int elements { get; internal set; }
            internal int max_depth;
            internal Error? error;
            internal bool child_error;

            // accessed only by the main thread
            public GLib.ListStore children_list_store { get; construct set; }
            public State state { get; internal set; }

            double _percent;
            public double percent {
                get { return _percent; }
                internal set {
                    _percent = value;

                    notify_property ("fraction");
                }
            }

            public double fraction {
                get {
                    return _percent / 100.0;
                }
            }

            // No need to notify that property when the number of children
            // changes as the whole model won't change once constructed.
            public bool is_empty {
                get { return children_list_store.n_items == 0; }
            }

            construct {
                children_list_store = new ListStore (typeof (Results));
            }

            public Results (FileInfo info, Results? parent_results) {
                parent = parent_results;
                name = info.get_name ();
                display_name = info.get_display_name ();
                if (display_name == null && name != null) {
                    display_name = Filename.display_name (name);
                }
                if (display_name == null) {
                    display_name = "";
                }
                file_type = info.get_file_type ();
                size = info.get_attribute_uint64 (FileAttribute.STANDARD_ALLOCATED_SIZE);
                if (size == 0) {
                    size = info.get_size ();
                }
                time_modified = info.get_attribute_uint64 (FileAttribute.TIME_MODIFIED);
                elements = 1;
                error = null;
                child_error = false;
            }

            public Results.for_process (string pid_str, string display_name, uint64 size, uint64 ppid, Results? parent_results) {
                parent = parent_results;
                name = pid_str;
                this.display_name = display_name;
                this.size = size;
                this.pid = uint64.parse(pid_str);
                elements = 1;
                error = null;
                child_error = false;
            }

            public Results.empty () {
            }

            public void update_with_child (Results child) {
                size         += child.size;
                elements     += child.elements;
                max_depth     = int.max (max_depth, child.max_depth + 1);
                child_error  |= child.child_error || (child.error != null);
                time_modified = uint64.max (time_modified, child.time_modified);
            }

            public int get_depth () {
                int depth = 1;
                for (var ancestor = parent; ancestor != null; ancestor = ancestor.parent) {
                    depth++;
                }
                return depth;
            }

            public bool is_ancestor (Results? descendant) {
                for (; descendant != null; descendant = descendant.parent) {
                    if (descendant == this)
                        return true;
                }
                return descendant == this;
            }

            public Gtk.TreeListModel create_tree_model () {
                return new Gtk.TreeListModel (children_list_store, false, false, (item) => {
                    var results = item as Scanner.Results;
                    return results == null ? null : results.children_list_store;
                });
            }
        }


        string get_process_display_name (string pid, string comm) {
            string contents;
            size_t length;
            try {
                if (FileUtils.get_contents ("/proc/%s/cmdline".printf (pid), out contents, out length)) {
                    string info = "";
                    string current_arg = "";
                    bool first = true;

                    for (int i = 0; i <= (int)length; i++) {
                        char c = (i < (int)length) ? contents[i] : '\0';
                        if (c == '\0') {
                            if (first) {
                                first = false;
                                current_arg = "";
                                if (i == (int)length) break;
                                continue;
                            }

                            if (current_arg != "") {
                                if (current_arg.has_prefix ("--type=")) {
                                    info = current_arg.substring (7);
                                    break;
                                }

                                if (!current_arg.has_prefix ("-")) {
                                    string arg = current_arg;
                                    if (arg.contains ("/")) {
                                        arg = Path.get_basename (arg);
                                    }

                                    // Ignore common interpreter names
                                    if (arg != "python" && arg != "python3" && arg != "node" && arg != "sh" && arg != "bash" && arg != "" && arg != comm) {
                                        info = arg;
                                        break;
                                    }
                                }
                            }
                            current_arg = "";
                            if (i == (int)length) break;
                        } else {
                            current_arg += c.to_string();
                        }
                    }

                    if (info != "") {
                        return "%s [%s]".printf (comm, info);
                    }
                }
            } catch (Error e) {}
            return comm;
        }

        void compute_sizes (Results res, HashTable<string, Results> process_map) {
            foreach (var child in process_map.get_values ()) {
                if (child.parent == res) {
                    compute_sizes (child, process_map);
                    res.update_with_child (child);
                }
            }
        }

        void* scan_in_thread () {
            try {
                var array = new ResultsArray ();

                // Virtual root
                var root_results = new Results.empty ();
                root_results.name = "root";
                root_results.display_name = _("System Processes");
                root_results.size = 0;

                var process_map = new HashTable<string, Results> (str_hash, str_equal);
                var ppid_map = new HashTable<string, string> (str_hash, str_equal);

                var dir = GLib.Dir.open ("/proc");
                string? name;
                long page_size = Posix.getpagesize ();
                if (page_size <= 0) page_size = 4096;

                while ((name = dir.read_name ()) != null) {
                    if (!((char)name[0]).isdigit ()) continue;

                    string stat_content;
                    if (FileUtils.get_contents ("/proc/%s/stat".printf (name), out stat_content)) {
                        int open_paren = stat_content.index_of ("(");
                        int close_paren = stat_content.last_index_of (")");
                        if (open_paren != -1 && close_paren != -1) {
                            string comm = stat_content.substring (open_paren + 1, close_paren - open_paren - 1);
                            string rest = stat_content.substring (close_paren + 2);
                            string[] parts = rest.split (" ");
                            if (parts.length > 1) {
                                string ppid = parts[1];

                                string statm_content;
                                uint64 rss = 0;
                                if (FileUtils.get_contents ("/proc/%s/statm".printf (name), out statm_content)) {
                                    string[] statm_parts = statm_content.split (" ");
                                    if (statm_parts.length > 1) {
                                        rss = uint64.parse (statm_parts[1]) * (uint64) page_size;
                                    }
                                }

                                string display_name = get_process_display_name (name, comm);
                                var res = new Results.for_process (name, display_name, rss, uint64.parse(ppid), null);
                                process_map.insert (name, res);
                                ppid_map.insert (name, ppid);
                            }
                        }
                    }
                }

                // Link children to parents
                foreach (unowned string pid in process_map.get_keys ()) {
                    var res = process_map.lookup (pid);
                    string ppid = ppid_map.lookup (pid);

                    var parent_res = process_map.lookup (ppid);
                    if (parent_res != null && ppid != pid) {
                        res.parent = parent_res;
                    } else {
                        res.parent = root_results;
                    }
                }

                // Calculate sizes
                compute_sizes (root_results, process_map);

                root_results.percent = 100.0;
                total_size = root_results.size;
                total_elements = (int) process_map.size ();

                // Pre-allocate array for results
                array.results = new Results[process_map.size () + 1];
                int i = 0;
                foreach (var res in process_map.get_values ()) {
                    if (res.parent != null && res.parent.size > 0) {
                        res.percent = 100.0 * (double) res.size / (double) res.parent.size;
                    }
                    array.results[i++] = res;
                }
                array.results[i++] = root_results;

                results_queue.push ((owned) array);
            } catch (Error e) {
            }

            // drop the thread's reference on the Scanner object
            this.self = null;
            return null;
        }

        bool process_results () {
            while (true) {
                var results_array = results_queue.try_pop ();

                if (results_array == null) {
                    break;
                }

                foreach (unowned Results results in results_array.results) {
                    if (results.parent != null) {
                        results.parent.children_list_store.insert (0, results);
                    }

                    if (results.child_error) {
                        results.state = State.CHILD_ERROR;
                    } else if (results.error != null) {
                        results.state = State.ERROR;
                    } else {
                        results.state = State.DONE;
                    }

                    if (results.max_depth > max_depth) {
                        max_depth = results.max_depth;
                    }

                    // We reached the root, we're done
                    if (results.parent == null) {
                        this.root = results;
                        scan_error = results.error;
                        successful = true;
                        completed ();
                        return false;
                    }
                }
            }

            return this.self != null;
        }

        void cancel_and_reset () {
            cancellable.cancel ();

            if (thread != null) {
                thread.join ();
                thread = null;
            }

            if (process_result_idle != 0) {
                GLib.Source.remove (process_result_idle);
                process_result_idle = 0;
            }

            // Drain the async queue
            var tmp = results_queue.try_pop ();
            while (tmp != null) {
                tmp = results_queue.try_pop ();
            }

            cancellable.reset ();
            scan_error = null;
            total_size = 0;
            total_elements = 0;

            excluded_locations = Application.get_default ().get_excluded_locations ();
        }

        public void scan (bool force) {
            if (force) {
                successful = false;
            }

            if (!successful) {
                cancel_and_reset ();

                // the thread owns a reference on the Scanner object
                this.self = this;

                thread = new Thread<void*> ("scanner", scan_in_thread);

                process_result_idle = Timeout.add (100, () => {
                        bool res = process_results();
                        if (!res) {
                            process_result_idle = 0;
                        }
                        return res;
                    });
            } else {
                completed ();
            }
        }

        public void cancel () {
            if (!successful) {
                cancel_and_reset ();
                scan_error = new IOError.CANCELLED ("Scan was cancelled");
            }
            completed ();
        }

        public void finish () throws Error {
            if (scan_error != null) {
                throw scan_error;
            }
        }

        public Scanner (File? directory, ScanFlags flags) {
            this.directory = directory;
            this.scan_flags = flags;
            cancellable = new Cancellable();
            scan_error = null;

            results_queue = new AsyncQueue<ResultsArray> ();
        }
    }
}
