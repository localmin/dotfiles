if &compatible
  set nocompatible
endif

syntax enable

" Highlight setting of the rows & colums 
set cursorline

filetype plugin indent on
" Remove the unnesessary preview window
set completeopt=menuone
" font size
" set guifont=Ricty\ Diminished\ Discord\ 11

" key mapping
"escape with jj  
inoremap <silent> jj <ESC>

" visual mode to ESC when Ctrl-j pushed 
vnoremap <silent> <C-j> <ESC>

" moving curosr of normal mode 
inoremap <C-j> <Down>
inoremap <C-k> <Up>
inoremap <C-h> <Left>
inoremap <C-l> <Right>

" insert blank line
nnoremap O :<C-u>call append(expand('.'), '')<ESC>
nnoremap o :<C-u>call append(expand('.'), '')<Cr>j
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

" clipboard setting
set clipboard=unnamed


"dein Scripts-----------------------------
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
let s:lazy_file = fnamemodify(expand('<sfile>'), ':h').'/.dein_lazy.toml'

if dein#load_state(s:dein_dir)
  call dein#begin(s:dein_dir)
  call dein#load_toml(s:toml_file, {'lazy': 0})
  call dein#load_toml(s:lazy_file, {'lazy': 1})
  call dein#end()
  call dein#save_state()
endif

" auto shortage plugin install 
if has('vim_starting') && dein#check_install()
  call dein#install()
endif
" }}}

" deoplete wake
"call dein#add('Shougo/deoplete.nvim')
"call dein#add('deoplete-plugin/deoplete-clang')
if !has('nvim')
  call dein#add('roxma/nvim-yarp')
  call dein#add('roxma/vim-hug-neovim-rpc')
endif

let g:deoplete#enable_at_startup = 1

"End dein Scripts-------------------------

" view EM space
""""""""""""""""""""""""""""""
function! ZenkakuSpace()
    highlight ZenkakuSpace cterm=underline ctermfg=lightblue guibg=darkgray
endfunction

if has('syntax')
    augroup ZenkakuSpace
        autocmd!
        autocmd ColorScheme * call ZenkakuSpace()
        autocmd VimEnter,WinEnter,BufRead * let w:m1=matchadd('ZenkakuSpace', '　')
    augroup END
    call ZenkakuSpace()
endif
""""""""""""""""""""""""""""""

" change status colors when insert mode or normal mode
""""""""""""""""""""""""""""""
let g:hi_insert = 'highlight StatusLine guifg=darkblue guibg=darkyellow gui=none ctermfg=blue ctermbg=yellow cterm=none'

if has('syntax')
  augroup InsertHook
    autocmd!
    autocmd InsertEnter * call s:StatusLine('Enter')
    autocmd InsertLeave * call s:StatusLine('Leave')
  augroup END
endif

let s:slhlcmd = ''
function! s:StatusLine(mode)
  if a:mode == 'Enter'
    silent! let s:slhlcmd = 'highlight ' . s:GetHighlight('StatusLine')
    silent exec g:hi_insert
  else
    highlight clear StatusLine
    silent exec s:slhlcmd
  endif
endfunction

function! s:GetHighlight(hi)
  redir => hl
  exec 'highlight '.a:hi
  redir END
  let hl = substitute(hl, '[\r\n]', '', 'g')
  let hl = substitute(hl, 'xxx', '', '')
  return hl
endfunction
""""""""""""""""""""""""""""""
colorscheme molokai
syntax on

let g:tex_conceal = ''

let g:indent_guides_enable_on_vim_startup = 1
let g:indent_guides_guide_size = 1
let g:indent_guides_start_level = 2

" watchdogs_checker/_ に設定を記述する事で全ての watchdogs_checker で有効になる
" hook/close_quickfix/enable_exit 1 で :WatchdogsRun 終了時に quickfix ウィンドウが閉じる
"let g:quickrun_config = {
"\   "watchdogs_checker/_" : {
"\       "hook/close_quickfix/enable_exit" : 1,
"\   },
"\}
"
"" watchdogs.vim の設定を追加
"call watchdogs#setup(g:quickrun_config)
" 書き込み後にシンタックスチェックを行う
let g:watchdogs_check_BufWritePost_enable = 1

" こっちは一定時間キー入力がなかった場合にシンタックスチェックを行う
" バッファに書き込み後、1度だけ行われる
let g:watchdogs_check_CursorHold_enable = 1
