"" ~/.vimrc — Editor C/C++ sobre Vim 9.2 (sin plugins, sin LSP)
"
" Entorno: CachyOS · Vim 9.2 · GCC 16 (C++23) · clang-format 23 · CMake 4.4 · Ninja · ctags
"
" Por qué NO hay LSP: Vim 9.2 ya no distribuye su runtime Lua (vim.api, vim.lsp,
" vim.fs y vim.diagnostic no existen; comprobado contra el Filelist del tag
" upstream v9.2.1164, que solo lleva dos .lua de test). Por eso la navegación
" semántica va con Universal Ctags y el diagnóstico con el propio g++ volcado
" en la quickfix. clangd sí está instalado y se usa vía :Check cuando quieras.

if exists('g:loaded_user_vimrc') | finish | endif
let g:loaded_user_vimrc = 1

" ─────────────────────────────────────────────────────────────────────────────
" 1. GENERAL
" ─────────────────────────────────────────────────────────────────────────────
set nocompatible
set encoding=utf-8
set fileencoding=utf-8
set hidden
set undofile
set undolevels=10000
set clipboard=unnamedplus
set mouse=a
set t_Co=256
set termguicolors

" ─────────────────────────────────────────────────────────────────────────────
" 2. ASPECTO
" ─────────────────────────────────────────────────────────────────────────────
syntax on
filetype plugin indent on
colorscheme habamax
set number relativenumber cursorline
set numberwidth=4
set signcolumn=yes
set laststatus=3
set fillchars=eob:\  vertalt:│
set splitbelow splitright
set display+=lastline
set scrolloff=5
set sidescrolloff=8

" ─────────────────────────────────────────────────────────────────────────────
" 3. BÚSQUEDA Y NAVEGACIÓN
" ─────────────────────────────────────────────────────────────────────────────
set incsearch hlsearch ignorecase smartcase wrapscan
set inccommand=nosplit
set showmode
nnoremap <Esc> <cmd>nohlsearch<CR>

nnoremap <ScrollWheelUp>     <C-u>
nnoremap <ScrollWheelDown>   <C-d>
nnoremap <S-ScrollWheelUp>   <C-b>
nnoremap <S-ScrollWheelDown> <C-f>
nnoremap <silent> H :left 999999999999999<CR>
nnoremap <silent> L :right 999999999999<CR>

" Ventanas
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l
nnoremap <C-w><S-l> :vertical resize +10<CR>

" ─────────────────────────────────────────────────────────────────────────────
" 4. C/C++ — sangrado, compilación, quickfix
" ─────────────────────────────────────────────────────────────────────────────
set expandtab tabstop=4 softtabstop=4 shiftwidth=4
set shiftround
set autoindent smartindent
set formatoptions-=c formatoptions+=j

" errorformat para gcc/clang y para rg. Cubre las cuatro formas que aparecen:
"   fichero:línea:col: error: texto   (g++/clang con columna y espacio)
"   fichero:línea:col:texto            (rg --column)
"   fichero:línea: error: texto        (gcc sin columna)
"   fichero:línea:texto                (rg sin columna)
" OJO: %f:%l:\ %m EXIGE un espacio tras los dos puntos; por eso rg, que emite
" fichero:línea:texto a secas, necesita además los patrones sin espacio.
" Sin '%m' suelto al final: haría entrar cada línea de contexto de gcc como
" una entrada lnum=0 y saturaría la quickfix.
set errorformat=%f:%l:%c:\ %m,%f:%l:%c:%m,%f:%l:\ %m,%f:%l:%m
set makeprg=g++
set switchbuf=useopen
set grepprg=rg\ --vimgrep
set grepformat=%f:%l:%c:%m

" ─────────────────────────────────────────────────────────────────────────────
" 5. COMANDOS C++  (lógica en ~/.vim/lua/user/cpp.lua)
"
" Las funciones Lua de aquí NO imprimen nada: este Vim no tiene echo()/
" echomsg()/echohl() y fn.execute() no produce salida visible. Por eso cada
" función devuelve el texto a mostrar y este vimscript lo presenta con
" "echo luaeval(...)". Para colorear el mensaje basta cambiar el :echohl.
" ─────────────────────────────────────────────────────────────────────────────
command! -nargs=* CMakeInit    echo luaeval("require('user.cpp').cmake_init(<q-args>)")
command!          CMakeBuild   echo luaeval("require('user.cpp').cmake_build_and_report()")
command!          CMakeRun     echo luaeval("require('user.cpp').cmake_run()")
command!          CMakeTest    echo luaeval("require('user.cpp').cmake_test()")
command!          CMakeGui     echo luaeval("require('user.cpp').cmake_open()")
command!          CtagsRefresh echo luaeval("require('user.cpp').gen_tags()")
command!          Check        echo luaeval("require('user.cpp').check_buffer()")
command!          References   echo luaeval("require('user.cpp').references()")
command!          Describe     echo luaeval("require('user.cpp').describe()")
command!          Format       echo luaeval("require('user.cpp').format()")
command! -nargs=* Comments     normal! gcc
command!          MakeTags     !ctags -R --languages=C,C++ --c++-kinds=+p --fields=+n+K-S --extras=+q --sort=foldcase --exclude=build --exclude=.git

" ─────────────────────────────────────────────────────────────────────────────
" 6. NAVEGACIÓN SEMÁNTICA (Universal Ctags)
" ─────────────────────────────────────────────────────────────────────────────
let mapleader = " "
set tags=./tags,~/.tags

nmap <C-]>      :tag <cword><CR>
nmap <C-t>      :pop<CR>
nmap <C-w>]     :tjump<CR>
nmap ]t         :tnorematch <cword><CR>
nmap [t         :tprevious<CR>
nmap <leader>a  :Tselect <cword><CR>
nmap K          :Describe<CR>
nmap <leader>r  :References<CR>
nmap <leader>tg :CtagsRefresh<CR>

" Con 'tags' en forma RELATIVA (./tags) el salto a la definición falla con
" E433 "No hay archivo de etiquetas" según desde dónde se abra el fichero. Se
" apunta siempre a una ruta ABSOLUTA: la del directorio de trabajo actual al
" arrancar, y la de la raíz del proyecto en cuanto se abre un fichero C++.
execute 'set tags=' . fnameescape(getcwd() . '/tags') . ',~/.tags'

" OJO: en los eventos BufRead* el patron casa con el NOMBRE DE FICHERO, no con
" el filetype, asi que "BufReadPost c,cpp" nunca llega a dispararse. Para
" reaccionar al filetype hay que usar el evento FileType.
autocmd FileType c,cpp lua require('user.cpp').ensure_tags()

" ─────────────────────────────────────────────────────────────────────────────
" 7. DIAGNÓSTICO, BUILD Y FORMATO
" ─────────────────────────────────────────────────────────────────────────────
nmap ]c         :cnext<CR>
nmap [c         :cprev<CR>
nmap <leader>c  :Check<CR>
nmap <leader>b  :CMakeBuild<CR>
nmap <leader>B  :CMakeRun<CR>
nmap <leader>CI :CMakeInit<CR>
nmap <leader>t  :CMakeTest<CR>
nmap <leader>cg :CMakeGui<CR>
nmap <leader>cf :Format<CR>
nmap <leader>i  echo luaeval("require('user.cpp').insert_include()")

" Completado por etiquetas (ctags)
set omnifunc=tagscomplete#tags#complete
inoremap <C-x><C-o> <C-x><C-o>

" ─────────────────────────────────────────────────────────────────────────────
" 8. AUTOCOMMANDS
" ─────────────────────────────────────────────────────────────────────────────
let g:cpp_files = '*.c,*.cc,*.cpp,*.cxx,*.h,*.hh,*.hpp,*.hxx'

" Formatear al guardar con clang-format (solo si el fichero parsea)
autocmd BufWritePost c,cpp
      \ if &modifiable && !&readonly && expand('%:p') !~# '/build/'
      \      | Format
      \ endif

" Regenerar etiquetas al guardar (desactivable con b:no_tags)
autocmd BufWritePost c,cpp
      \ if !get(b:, 'no_tags', 0) && !filereadable(expand('%:p:h/tags'))
      \      | CtagsRefresh
      \ endif

" Aviso de error de sintaxis al guardar
autocmd BufWritePost c,cpp
      \ if v:shell_error != 0
      \      echohl ErrorMsg
      \      echomsg '[c++] Error de compilación al guardar (revisa :messages)'
      \      echohl NONE
      \ endif

" Resaltar la línea del cursor
autocmd CursorMoved c,cpp
      \ if line('.') != line('w0')
      \      call matchadd('Visual', '\%' . line('.') . '>.*\%<' . (line('.') + 1) . '>')
      \ endif

" Opciones específicas de C/C++
" OJO: nada de 'iskeyword+=:>' — iskeyword solo admite letras, digitos, '_',
'@', '-' y los bytes 192-255; ':' (58) y '>' (62) dan
" "E474: argumento no válido" en cuanto se abre un fichero C++.
autocmd FileType c,cpp setlocal include=^\s*#\s*include
autocmd FileType c,cpp setlocal suffixesadd=.cpp,.cxx,.cc,.hpp,.hh,.h

" ─────────────────────────────────────────────────────────────────────────────
" 9. STATUSLINE
" ─────────────────────────────────────────────────────────────────────────────
function! s:StatusLine() abort
  let l:mode = mode()
  let l:pos  = printf('%3d:%-3d', line('.'), col('.'))
  let l:ft   = empty(&filetype) ? '' : ' ' . &filetype
  let l:prog = get(b:, 'cpp_target', '')
  let l:right = l:mode . ' │ ' . l:pos . l:ft
  let l:prog  = l:prog ==# '' ? '' : ' ▸ ' . l:prog
  return '%f%h%w%r%=' . l:prog . ' %-14.(%l,%c%V%) %y ' . l:right
endfunction
set statusline=%!v:lua.eval('v:lua.s_StatusLine()')
highlight statusline   ctermbg=236 ctermfg=255 termbg=236 termfg=255
highlight statuslineNC ctermbg=236 ctermfg=244 termbg=236 termfg=244

" ─────────────────────────────────────────────────────────────────────────────
" 10. OPCIONES DE PROYECTO
" ─────────────────────────────────────────────────────────────────────────────
" b:cpp_standard  -> 'c++23' por defecto; lo usa :Check
" b:cpp_namespace -> p. ej. 'miapp'; lo usa <leader>i
" b:cpp_target    -> nombre mostrado en la statusline
" b:no_tags       -> 1 desactiva la regeneración de tags al guardar

" ─────────────────────────────────────────────────────────────────────────────
" 11. MENSAJES
" ─────────────────────────────────────────────────────────────────────────────
set shortmess+=I
set cmdheight=1
set lazyredraw
set report=9999

" ---------------------------------------------------------------- vim: ts=4 sw=4 et fdm=marker