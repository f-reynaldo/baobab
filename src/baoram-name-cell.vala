/* -*- tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*- */
/* Baoram - Memory Usage Analyzer
 *
 * Copyright © 2024 Adrien Plazas <aplazas@gnome.org>
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

namespace Baoram {

    [GtkTemplate (ui = "/freynaldo/baoram/ui/baoram-name-cell.ui")]
    public class NameCell : Adw.Bin {
        public Scanner.Results? item { set; get; }

        construct {
            notify["item"].connect (on_notify_item_cb);
        }

        private void on_notify_item_cb () {
            if (item == null) {
                remove_css_class ("baoram-cell-error");
                remove_css_class ("baoram-cell-warning");

                return;
            }

            switch (item.state) {
            case Scanner.State.ERROR:
                add_css_class ("baoram-cell-error");
                break;
            case Scanner.State.CHILD_ERROR:
                add_css_class ("baoram-cell-warning");
                break;
            default:
                remove_css_class ("baoram-cell-error");
                remove_css_class ("baoram-cell-warning");
                break;
            }
        }
    }
}
