#!/bin/sh
#gitconfig
ln -sf ~/dotfiles/.gitconfig ~/.gitconfig
# vim
# Maybe you should wake up gvim once...
mkdir -p ~/.vim
mkdir -p ~/dotfiles/vim/dein/repos/github.com/Shougo/dein.vim
git clone https://github.com/Shougo/dein.vim.git \
    ~/dotfiles/vim/dein/repos/github.com/Shougo/dein.vim
ln -sf ~/dotfiles/vim/dein ~/.vim
ln -sf ~/dotfiles/vim/.dein.toml ~/.dein.toml
ln -sf ~/dotfiles/vim/.vimrc ~/.vimrc

# etc
ln -sf ~/dotfiles/.bashrc ~/.bashrc
ln -sf ~/dotfiles/.bash_profile  ~/.bash_profile
ln -sf ~/dotfiles/.tigrc ~/.tigrc
ln -sf ~/dotfiles/.tmux.conf ~/.tmux.conf
