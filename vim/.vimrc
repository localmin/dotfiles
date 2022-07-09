" Check vi compatibility
if &compatible
  set nocompatible
endif
" language setting
lan C

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

" Split window
nmap ss :split<Return><C-w>w
nmap sv :vsplit<Return><C-w>w

" Move window
nmap <Tab> <C-w>w
map sh <C-w>h
map sk <C-w>k
map sj <C-w>j
map sl <C-w>l

" close window
nmap cc :close<CR>

" Switch buffer
nnoremap <Space> :bnext<CR>
" close buffer
nnoremap bb :bd<CR>

" insert blank line
nnoremap O :<C-u>call append(expand('.'), '')<ESC>
" Ale jump setting
nmap <silent> <C-k> <Plug>(ale_previous_wrap)
nmap <silent> <C-j> <Plug>(ale_next_wrap)

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
set termguicolors
let &t_8f = "\<Esc>[38;2;%lu;%lu;%lum"
let &t_8b = "\<Esc>[48;2;%lu;%lu;%lum"

set background=dark
colorscheme oceanic_material

syntax on

let g:tex_conceal = ''

let g:indent_guides_enable_on_vim_startup = 1
let g:indent_guides_guide_size = 1
let g:indent_guides_start_level = 2

" Setting for alrline
let g:airline_powerline_fonts = 1
set laststatus=2
let g:airline_theme = "tokyonight"

if !exists('g:airline_symbols')
    let g:airline_symbols = {}
endif

" Separater on the leftside
let g:airline_left_sep = '⮀'
let g:airline_left_alt_sep = '⮁'

" Separater on the rightside
let g:airline_symbols.crypt = '🔒'
let g:airline_symbols.linenr = '¶'
let g:airline_symbols.branch = '⭠'
let g:airline_symbols.whitespace = 'Ξ'
let g:airline_symbols.maxlinenr = '㏑'
let g:airline_symbols.colnr = 'CL:'

" Tab setting on Airline
let g:airline#extensions#tabline#enabled = 1
nmap <C-p> <Plug>AirlineSelectPrevTab
nmap <C-n> <Plug>AirlineSelectNextTab


" vim -b : edit binary using  Vinaraise
augroup BinaryXXD
autocmd!
    autocmd BufReadPre  *.bin let &binary =1
    autocmd BufReadPost * if &binary | Vinarise
    autocmd BufWritePre * if &binary | Vinarise | endif
    autocmd BufWritePost * if &binary | Vinarise
augroup END

" For defx setting
set encoding=utf-8

call defx#custom#option('_', {
      \'columns': 'indent:git:icons:filename',
  	  \ 'show_ignored_files': 1,
			\ })

" Define mappings
nnoremap <silent>sf :<C-u>Defx -listed -resume
      \ -columns=indent:mark:icon:icons:filename:git:size
      \ -buffer-name=tab`tabpagenr()`
      \ `expand('%:p:h')` -search-recursive=`expand('%:p')`<CR>

autocmd FileType defx call s:defx_my_settings()
	function! s:defx_my_settings() abort
    "Define mappings
	  nnoremap <silent><buffer><expr> yy
	  \ defx#do_action('copy')
	  nnoremap <silent><buffer><expr> p
	  \ defx#do_action('paste')
	  nnoremap <silent><buffer><expr> l
	  \ defx#do_action('open')
	  nnoremap <silent><buffer><expr> E
	  \ defx#do_action('open', 'vsplit')
	  nnoremap <silent><buffer><expr> o
	  \ defx#do_action('open_or_close_tree')
	  nnoremap <silent><buffer><expr> K
	  \ defx#do_action('new_directory')
	  nnoremap <silent><buffer><expr> N
	  \ defx#do_action('new_file')
	  nnoremap <silent><buffer><expr> C
	  \ defx#do_action('toggle_columns',
	  \                'mark:indent:icon:filename:type:size:time')
	  nnoremap <silent><buffer><expr> r
	  \ defx#do_action('rename')
	  nnoremap <silent><buffer><expr> d
	  \ defx#do_action('remove')
	  nnoremap <silent><buffer><expr> c
	  \ defx#do_action('yank_path')
	  nnoremap <silent><buffer><expr> .
	  \ defx#do_action('toggle_ignored_files')
	  nnoremap <silent><buffer><expr> h
	  \ defx#do_action('cd', ['..'])
	  nnoremap <silent><buffer><expr> q
	  \ defx#do_action('quit')
	  nnoremap <silent><buffer><expr> <Space>
	  \ defx#do_action('toggle_select') . 'j'
	  nnoremap <silent><buffer><expr> *
	  \ defx#do_action('toggle_select_all')
	  nnoremap <silent><buffer><expr> j
	  \ line('.') == line('$') ? 'gg' : 'j'
	  nnoremap <silent><buffer><expr> k
	  \ line('.') == 1 ? 'G' : 'k'
	  nnoremap <silent><buffer><expr> <C-l>
	  \ defx#do_action('redraw')
	endfunction
" defx default icons setting
call defx#custom#column('icon', {
      \ 'directory_icon': '▸',
      \ 'opened_icon': '▾',
      \ 'root_icon': ' ',
      \ })

" defx-icons settings 
let g:defx_icons_enable_syntax_highlight = 0
let g:defx_icons_column_length = 2
let g:defx_icons_directory_icon = ''
let g:defx_icons_mark_icon = '*'
let g:defx_icons_copy_icon = ''
let g:defx_icons_move_icon = ''
let g:defx_icons_parent_icon = ''
let g:defx_icons_default_icon = ''
let g:defx_icons_link_icon = ''
let g:defx_icons_directory_symlink_icon = ''
let g:defx_icons_root_opened_tree_icon = ''
let g:defx_icons_nested_opened_tree_icon = ''
let g:defx_icons_nested_closed_tree_icon = ''

" defx-git setting
call defx#custom#column('git', 'indicators', {
  \ 'Modified'  : 'M',
  \ 'Staged'    : '✚',
  \ 'Untracked' : '✭',
  \ 'Renamed'   : '➜',
  \ 'Unmerged'  : '═',
  \ 'Ignored'   : '☒',
  \ 'Deleted'   : '✖',
  \ 'Unknown'   : '?'
  \ })
