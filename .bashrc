# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
[ -z "$PS1" ] && return

# don't put duplicate lines in the history. See bash(1) for more options
# ... or force ignoredups and ignorespace
HISTCONTROL=ignoredups:ignorespace:erasedups

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
export HISTSIZE=5000
export HISTFILESIZE=1000000

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "$debian_chroot" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

if [[ -t 1 ]] &&
	command -v tput >/dev/null 2>&1 &&
	(( $(tput colors 2>/dev/null || echo 0) >= 8 )); then
	__color_prompt() {
		echo -n '\[\e['"$1"'m\]'
		echo -n "$2"
		echo -n '\[\e[0m\]'
	}
else
	__color_prompt() {
		echo -n "$2"
	}
fi

__prompt_command() {
	local exit=$?

	PS1='${debian_chroot:+($debian_chroot)}'
	! test -f .bashrc_singleusermode && {
		PS1+="$(__color_prompt '1;36' '\u')"
			PS1+='-'
		}
	PS1+="$(__color_prompt '1;36' '\h')"
	PS1+='@'
	PS1+="$(__color_prompt '33' '\t')"
	PS1+=':'
	PS1+="$(__color_prompt '1;34' '\W')"
	(( exit != 0 )) && PS1+=$(__color_prompt '1;31' "✘$exit")
	PS1+='\$ '
}

PROMPT_COMMAND=__prompt_command

#test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
#
alias ls='ls --color=auto'
#alias dir='dir --color=auto'
#alias vdir='vdir --color=auto'

alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# alias curl='curl -s'
alias vim=nvim

# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

if [ -f ~/.bash_aliases ]; then
	. ~/.bash_aliases
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if [ -f /etc/bash_completion ] && ! shopt -oq posix; then
	. /etc/bash_completion
fi

if [ -f ~/.bash_work ]; then
	. ~/.bash_work
fi

if [ -d ~/.bashrc.d ]; then
	for f in ~/.bashrc.d/*; do
		[ -e "$f" ] &&
		[ -f "$f" ] &&
		source "$f"
	done
fi

# my settings

# fix green not readable background to o+w dirs
#export LS_COLORS=$LS_COLORS:"ow=34;40"

export PATH="$HOME/.local/bin:$PATH"

export GOPROXY=direct
export GOPATH="$HOME/.go"
export GOBIN="$GOPATH/bin"
export PATH="$GOBIN:$PATH"
export GOWORK=off
export COMPOSE_BAKE=true

alias gochroma="chroma -l go -f terminal256 -s swapoff"

cgodoc() {
	go doc "$@" | gochroma
}

export GPG_TTY=$(tty)

# vim: ts=4 sw=4 noet
