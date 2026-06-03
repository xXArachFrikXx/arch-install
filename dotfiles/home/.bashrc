#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# Add user scripts to PATH (theme-switch, theme-init, rofi-wallpaper live here)
export PATH="$HOME/.local/bin:$PATH"

alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias ff='fastfetch'
eval "$(starship init bash)"
