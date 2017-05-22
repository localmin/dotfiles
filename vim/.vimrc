set nocompatible

syntax enable

filetype plugin indent on


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

" separate window
function! s:auto_sep()
  rightbelow vsplit ~/_vimrc 
  wincmd p
endfunction

augroup AUTO_SEP
 au!
 autocmd VimEnter * call s:auto_sep()
augroup END
set columns=270
set lines=75

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
