#!/bin/sh
# vim
ln -sf ~/dotfiles/vim/colors ~/.vim
ln -sf ~/dotfiles/vim/.vimrc ~/.vimrc
mkdir -p ~/.vim/dein/repos/github.com/Shougo/dein.vim
git clone https://github.com/Shougo/dein.vim.git \
    ~/.vim/dein/repos/github.com/Shougo/dein.vim
ln -sf ~/dotfiles/vim/.dein.toml ~/.dein.toml

# sublimetext3
ln -sf ~/dotfiles/sublimetext3/Packages ~/.config/sublime-text-3/Packages
ln -sf ~/dotfiles/sublimetext3/Installed\ Packages ~/.config/sublime-text-3/Installed\ Packages

# etc
ln -sf ~/dotfiles/.bashrc ~/.bashrc