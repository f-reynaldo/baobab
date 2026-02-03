vapi_sources = [
  'config.vapi',
]

baoram_vala_sources = [
  'baoram-application.vala',
  'baoram-cellrenderers.vala',
  'baoram-chart.vala',
  'baoram-contents-cell.vala',
  'baoram-file-cell.vala',
  'baoram-folder-cell.vala',
  'baoram-folder-display.vala',
  'baoram-location-list.vala',
  'baoram-location.vala',
  'baoram-name-cell.vala',
  'baoram-pathbar.vala',
  'baoram-preferences-dialog.vala',
  'baoram-progress-cell.vala',
  'baoram-ringschart.vala',
  'baoram-scanner.vala',
  'baoram-size-cell.vala',
  'baoram-time-modified-cell.vala',
  'baoram-tree-list-row-sorter.vala',
  'baoram-treemap.vala',
  'baoram-window.vala',
  'main.vala'
]

baoram_sources = [
  vapi_sources,
  baoram_vala_sources,
  resources
]

baoram_vala_args = [
  '--target-glib', '2.44',
  '--vapidir', meson.current_source_dir(),
  '--gresources', resource_files,
  '--pkg', 'posix',
]

baoram_c_args = [
  '-include', 'config.h'
]

baoram_dependencies = [
  glib,
  gio,
  gobject,
  gtk,
  libhandy,
  math
]

executable('baoram', baoram_sources,
  include_directories: config_h_dir,
  vala_args: baoram_vala_args,
  c_args: baoram_c_args,
  dependencies: baoram_dependencies,
  export_dynamic: true,
  win_subsystem: 'windows',
  install: true
)
