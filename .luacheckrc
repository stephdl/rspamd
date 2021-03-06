codes = true
std = 'min'

exclude_files = {
  '/**/contrib/**',
  '/**/test/lua/**',
  '/**/test/functional/lua/miltertest/**',
  '/**/test/functional/lua/rspamadm/**',
  '.git/**/',
}

globals = {
  'check_header_delimiter_empty',
  'check_header_delimiter_tab',
  'classifiers',
  'config',
  'confighelp',
  'kmail_msgid',
  'rspamd_classifiers',
  'rspamd_config',
  'rspamd_count_metatokens',
  'rspamd_gen_metatokens',
  'rspamd_parse_redis_server',
  'rspamd_paths',
  'rspamd_plugins',
  'rspamd_redis_make_request',
  'rspamd_str_split',
  'rspamd_version',
  'rspamd_map_add',
  'rspamd_maps',
  'rspamd_plugins_state',
  'rspamadm',
  'loadstring',
  'rspamadm_ev_base',
  'rspamadm_session',
}

ignore = {
  '212', -- unused argument
  '612', -- trailing whitespace
  '631', -- line is too long
}

files['/**/src/plugins/lua/spamassassin.lua'].globals = {
  'ffi',
  'jit',
}

files['/**/src/plugins/lua/greylist.lua'].globals = {
  'math.ifloor',
}

files['/**/lualib/lua_util.lua'].globals = {
  'table.unpack',
  'unpack',
}

files['/**/lualib/lua_redis.lua'].globals = {
  'rspamadm_ev_base',
}

files['/**/src/rspamadm/*'].globals = {
  'ansicolors',
  'getopt',
}
