icondir = join_paths(get_option('datadir'), 'icons/hicolor')
foreach size: ['scalable', 'symbolic']
  install_subdir('icons/hicolor/' + size, install_dir: icondir)
endforeach

resource_files = files('baoram.gresource.xml')
resources = gnome.compile_resources('freynaldo.baoram', resource_files, c_name: 'resources')

install_man ('baoram.1')

desktop_file = i18n.merge_file(
  input: 'freynaldo.baoram.desktop.in',
  output: 'freynaldo.baoram.desktop',
  type: 'desktop',
  po_dir: '../po',
  install: true,
  install_dir: join_paths(get_option('datadir'), 'applications'),
)

appdata_file = i18n.merge_file(
  input: 'freynaldo.baoram.metainfo.xml.in',
  output: 'freynaldo.baoram.metainfo.xml',
  po_dir: '../po',
  install: true,
  install_dir: join_paths(get_option('datadir'), 'metainfo'),
)# Validating app data

appstreamcli = find_program('appstreamcli', required: false)
if appstreamcli.found()
  test(
    'validate-appdata', appstreamcli,
    args: [
      'validate', '--no-net', '--explain', appdata_file.full_path()
    ]
  )
endif

install_data (
  'freynaldo.baoram.gschema.xml',
  install_dir: join_paths(get_option('datadir'), 'glib-2.0', 'schemas')
)

service_conf = configuration_data ()
service_conf.set ('bindir', join_paths (get_option('prefix'), get_option('bindir')))

configure_file (
  input: 'freynaldo.baoram.service.in',
  output: 'freynaldo.baoram.service',
  configuration: service_conf,
  install_dir: join_paths(get_option('datadir'), 'dbus-1', 'services')
)

