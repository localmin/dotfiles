# /etc/skel/.bashrc
#
# This file is sourced by all *interactive* bash shells on startup,
# including some apparently interactive shells such as scp and rcp
# that can't tolerate any output.  So make sure this doesn't display
# anything or bad things will happen !


# Test for an interactive shell.  There is no need to set anything
# past this point for scp and rcp, and it's important to refrain from
# outputting anything in those cases.
if [[ $- != *i* ]] ; then
    # Shell is non-interactive.  Be done now!
    return
fi

# Put your fun stuff here.
# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# git completion
source /opt/homebrew/etc/bash_completion.d/git-prompt.sh
source /opt/homebrew/etc/bash_completion.d/git-completion.bash
GIT_PS1_SHOWDIRTYSTATE=true
PS1=' \[\033[33m\]\w\[\033[31m\]:($(uname -m))\[\033[36m\]$(__git_ps1 [%s])\n\[\e[0;32m\]( ╹◡╹) \[\e[0;37m'
# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    #alias ls='ls --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'
 
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi
  
# add
# LuaJitTex
alias luajitlatex='luajittex --fmt=luajitlatex.fmt'
alias lmk='latexmk -pvc'
# ls color
export LSCOLORS=gxfxcxdxbxegedabagacad
alias ls='ls -G'

export GOPATH=$HOME
export PATH=$PATH:$GOPATH/bin

alias g='cd $(ghq list --full-path | peco)'
alias gh='hub browse $(ghq list --full-path| peco | cut -d "/" -f 2,3)'

# ghidra
alias ghidra='/Users/localmin/Downloads/ghidra_9.1.2_PUBLIC/ghidraRun'

# brew setting
alias arm="exec arch -arch arm64e /bin/bash"
alias x64="exec arch -arch x86_64 /bin/bash"

# exa config
# alias ls="exa -hGF --icons"
alias ls="eza --icons --git --time-style relative"

# bat config
alias cat="bat -p"

# nvm config 
export NVM_DIR="$HOME/.nvm"
  [ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"  # This loads nvm
  [ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"  # This loads nvm bash_completion

# setting nodebrew
export PATH=$HOME/.nodebrew/current/bin:$PATH

#alias vim="nvim"
#alias vi="nvim"
