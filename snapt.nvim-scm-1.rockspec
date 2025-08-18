---@diagnostic disable: lowercase-global
rockspec_format = '3.0'
package = 'snapt.nvim'
version = 'scm-1'

test_dependencies = {
  'lua >= 5.1',
  'nlua',
}

source = {
  url = 'git://github.com/MagicDuck/' .. package,
}

build = {
  type = 'builtin',
}
