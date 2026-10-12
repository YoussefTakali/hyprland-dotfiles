# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="agnosterzak-mocha"

plugins=( 
    git
    dnf
    zsh-autosuggestions
    zsh-syntax-highlighting
)

source $ZSH/oh-my-zsh.sh

# check the dnf plugins commands here
# https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/dnf


# Display Pokemon-colorscripts
# Project page: https://gitlab.com/phoneybadger/pokemon-colorscripts#on-other-distros-and-macos
#pokemon-colorscripts --no-title -s -r #without fastfetch
#pokemon-colorscripts --no-title -s -r | fastfetch -c $HOME/.config/fastfetch/config-pokemon.jsonc --logo-type file-raw --logo-height 10 --logo-width 5 --logo -

# Startup card: current wallpaper (rounded, via kitty graphics) + system summary
if [[ $TERM == xterm-kitty ]] && _ff_logo=$("$HOME/.config/fastfetch/wall-logo.sh"); then
    fastfetch -c "$HOME/.config/fastfetch/config-wall.jsonc" --logo-type kitty-direct --logo "$_ff_logo"
else
    fastfetch -c "$HOME/.config/fastfetch/config-wall.jsonc" --logo-type builtin --logo fedora_small
fi
unset _ff_logo

# fastfetch. Will be disabled if above colorscript was chosen to install
#fastfetch -c $HOME/.config/fastfetch/config-compact.jsonc

# Set-up FZF key bindings (CTRL R for fuzzy history finder)
source <(fzf --zsh)

HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt appendhistory

# Set-up icons for files/directories in terminal using lsd
alias ls='lsd'
alias l='ls -l'
alias la='ls -a'
alias lla='ls -la'
alias lt='ls --tree'


# Load Angular CLI autocompletion.
command -v ng >/dev/null && source <(ng completion script)
export PATH="$HOME/.local/bin:$PATH"
