#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '

# OpenCode global tools (ECC and bundled Node runtime)
case ":$PATH:" in
  *:"$HOME/.config/opencode/bin":*) ;;
  *) export PATH="$HOME/.config/opencode/bin:$PATH" ;;
esac



# Added by Antigravity CLI installer
export PATH="/home/omicron/.local/bin:$PATH"
. "$HOME/.cargo/env"
