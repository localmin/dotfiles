#!/bin/sh
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

# Claude Code user settings (deny list / sandbox / model etc.)
# Needs jq for the statusLine script.
mkdir -p ~/.claude
ln -sf ~/dotfiles/.claude/settings.json ~/.claude/settings.json
ln -sf ~/dotfiles/.claude/statusline-command.sh ~/.claude/statusline-command.sh
# Resume-context hooks (SessionStart surfaces WIP.md + git status; PreCompact reminds to flush).
mkdir -p ~/.claude/hooks
ln -sf ~/dotfiles/.claude/hooks/resume-context.sh ~/.claude/hooks/resume-context.sh
ln -sf ~/dotfiles/.claude/hooks/precompact-flush.sh ~/.claude/hooks/precompact-flush.sh
