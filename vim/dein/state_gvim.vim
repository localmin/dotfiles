if g:dein#_cache_version != 100 | throw 'Cache loading error' | endif
let [plugins, ftplugin] = dein#load_cache_raw(['/home/localmin/.vimrc', '/home/localmin/.dein.toml'])
if empty(plugins) | throw 'Cache loading error' | endif
let g:dein#_plugins = plugins
let g:dein#_ftplugin = ftplugin
let g:dein#_base_path = '/home/localmin/.vim/dein'
let g:dein#_runtime_path = '/home/localmin/.vim/dein/.cache/.vimrc/.dein'
let g:dein#_cache_path = '/home/localmin/.vim/dein/.cache/.vimrc'
let &runtimepath = '/home/localmin/.vim/dein/repos/github.com/Shougo/dein.vim,/home/localmin/.vim,/home/localmin/.vim/dein/.cache/.vimrc/.dein,/usr/share/vim/site,/usr/share/vim/current,/home/localmin/.vim/dein/.cache/.vimrc/.dein/after,/usr/share/vim/site/after,/home/localmin/.vim/after'
filetype off
