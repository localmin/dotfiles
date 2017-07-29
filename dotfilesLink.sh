#!/bin/sh
# vim
# Maybe you should wake up gvim once...
mkdir -p ~/.vim
mkdir -p ~/dotfiles/vim/dein/repos/github.com/Shougo/dein.vim
git clone https://github.com/Shougo/dein.vim.git \
    ~/dotfiles/vim/dein/repos/github.com/Shougo/dein.vim
ln -sf ~/dotfiles/vim/dein ~/.vim/dein
ln -sf ~/dotfiles/vim/.dein.toml ~/.dein.toml
ln -sf ~/dotfiles/vim/colors ~/.vim/colors
ln -sf ~/dotfiles/vim/.vimrc ~/.vimrc

# sublimetext3
ln -sf ~/dotfiles/sublimetext3/Packages ~/.config/sublime-text-3/Packages
ln -sf ~/dotfiles/sublimetext3/Installed\ Packages ~/.config/sublime-text-3/Installed\ Packages

# etc
ln -sf ~/dotfiles/.bashrc ~/.bashrc