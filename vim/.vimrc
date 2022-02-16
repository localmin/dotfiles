" Check vi compatibility
if &compatible
  set nocompatible
endif

syntax enable

" Highlight setting of the rows.
set cursorline

" Add file detection and indent setting for the lang you open
filetype plugin indent on

" Remove the unnesessary preview window
set completeopt=menuone

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

if dein#load_state(s:dein_dir)
  call dein#begin(s:dein_dir)
  call dein#load_toml(s:toml_file, {'lazy': 0})
  call dein#end()
  call dein#save_state()
endif

" auto shortage plugin install 
if has('vim_starting') && dein#check_install()
  call dein#install()
endif
" }}}

" Delete plugins when they are removed in .dein.toml or .dein_lazy.toml
let s:removed_plugins = dein#check_clean()
if len(s:removed_plugins)>0 
    call map(s:removed_plugins, "delete(v:val, 'rf')")
    call dein#recache_runtimepath()
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
" colorscheme molokai
set termguicolors

let g:tokyonight_style = 'night' " available: night, storm
let g:tokyonight_enable_italic = 1

colorscheme tokyonight

syntax on

let g:tex_conceal = ''

let g:indent_guides_enable_on_vim_startup = 1
let g:indent_guides_guide_size = 1
let g:indent_guides_start_level = 2

" Setting of watchdogs
" Close the quickfix window after using sysntax checking
let g:quickrun_config = {
\   "watchdogs_checker/_" : {
\       'outputter/quickfix/open_cmd' : '',
\   },
\}

" call watchdogs#setup(g:quickrun_config)
" Syntax checking after writng 
let g:watchdogs_check_BufWritePost_enable = 1
" Auto Syntax checking at regular interval
let g:watchdogs_check_CursorHold_enable = 1

" Quickfix setting
nnoremap <silent><C-o> :copen<CR>
nnoremap <silent><C-c> :cclose<CR>
nnoremap <silent>gt <C-w><C-w>

" Setting for alrline
let g:airline_powerline_fonts = 1
set laststatus=2
let g:airline_theme = 'luna'

if !exists('g:airline_symbols')
	let g:airline_symbols = {}
endif

" Separater on the leftside
let g:airline_left_sep = '⮀'
let g:airline_left_alt_sep = '⮁'

" Separater on the rightside
let g:airline_right_sep = '⮂'
let g:airline_right_alt_sep = '⮃'
let g:airline_symbols.crypt = '🔒'
let g:airline_symbols.linenr = '¶'
let g:airline_symbols.maxlinenr = '㏑'
let g:airline_symbols.branch = '⭠'
let g:airline_symbols.paste = 'ρ'
let g:airline_symbols.spell = 'Ꞩ'
let g:airline_symbols.notexists = '∄'
let g:airline_symbols.whitespace = 'Ξ'

" Tab setting on Airline
let g:airline#extensions#tabline#enabled = 1
nmap <C-p> <Plug>AirlineSelectPrevTab
nmap <C-n> <Plug>AirlineSelectNextTab

let g:airline_theme = "tokyonight"

" vim -b : edit binary using  Vinaraise
augroup BinaryXXD
	autocmd!
	autocmd BufReadPre  *.bin let &binary =1
	autocmd BufReadPost * if &binary | Vinarise
	autocmd BufWritePre * if &binary | Vinarise | endif
	autocmd BufWritePost * if &binary | Vinarise 
augroup END
