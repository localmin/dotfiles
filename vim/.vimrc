set nocompatible

syntax enable

filetype plugin indent on

" Tab setting
set tabstop=4
set autoindent
set expandtab
set shiftwidth=4

" ruler & colum numbering
set ruler
set number

" ignore upper case letters when using lower case letters for search
set smartcase

" show unvisual letters
set list  
" - means "tab"
set listchars=tab:>-,trail:.  

" separate window
function! s:auto_sep()
  rightbelow vsplit ~/_vimrc 
  wincmd p
endfunction

augroup AUTO_SEP
 au!
 autocmd VimEnter * call s:auto_sep()
augroup END


"dein Scripts-----------------------------
if !&compatible
  set nocompatible
endif

" reset augroup
augroup MyAutoCmd
  autocmd!
augroup END

" dein settings {{{
" auto dein install
let s:cache_home = empty($XDG_CACHE_HOME) ? expand('~/.vim') : $XDG_CACHE_HOME
let s:dein_dir = s:cache_home . '/dein'
let s:dein_repo_dir = s:dein_dir . '/repos/github.com/Shougo/dein.vim'
if !isdirectory(s:dein_repo_dir)
  call system('git clone https://github.com/Shougo/dein.vim ' . shellescape(s:dein_repo_dir))
endif
let &runtimepath = s:dein_repo_dir .",". &runtimepath

" read cached & make plugin
let s:toml_file = fnamemodify(expand('<sfile>'), ':h').'/.dein.toml'
if dein#load_state(s:dein_dir)
  call dein#begin(s:dein_dir, [$MYVIMRC, s:toml_file])
  call dein#load_toml(s:toml_file)
  call dein#end()
  call dein#save_state()
endif

" auto shortage plugin install 
if has('vim_starting') && dein#check_install()
  call dein#install()
endif
" }}}

" starting NERDTree when no argument
let file_name = expand('%')
if has('vim_starting') &&  file_name == ''
  autocmd VimEnter * NERDTree ./
endif
 
"End dein Scripts-------------------------


colorscheme molokai
syntax on