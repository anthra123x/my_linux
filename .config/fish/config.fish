# User-local executables
fish_add_path "$HOME/.local/bin"

# Commands to run in interactive sessions can go here
if status is-interactive
    # No greeting
    set fish_greeting

    # Mostrar fastfetch con el logotipo de microarquitectura de Omicron
    if test "$TERM" = "xterm-kitty" -a -z "$VSCODE_INJECTION"
        fastfetch
    end

    # Use starship
    function starship_transient_prompt_func
        starship module character
    end
    if test "$TERM" != "linux"
        starship init fish | source
        enable_transience
    end
    
    # Colors (solo para emuladores distintos a kitty para preservar el tema Late Night exacto de Kitty)
    if test "$TERM" != "xterm-kitty" -a -f ~/.local/state/quickshell/user/generated/terminal/sequences.txt
        cat ~/.local/state/quickshell/user/generated/terminal/sequences.txt
    end

    # Aliases
    alias neofetch 'fastfetch'
    # kitty doesn't clear properly so we need to do this weird printing
    alias clear "printf '\033[2J\033[3J\033[1;1H'"
    alias celar "printf '\033[2J\033[3J\033[1;1H'"
    alias claer "printf '\033[2J\033[3J\033[1;1H'"
    alias pamcan pacman
    alias q 'qs -c ii'
    if test "$TERM" != "linux"
        alias ls 'eza --icons=auto'
    end
    if test "$TERM" = "xterm-kitty"
        alias ssh 'kitten ssh'
    end
end

# bun
set --export BUN_INSTALL "$HOME/.bun"
set --export PATH $BUN_INSTALL/bin $PATH


# Added by Antigravity CLI installer
set -gx PATH "/home/omicron/.local/bin" $PATH

fish_add_path /home/omicron/.spicetify


# Memory and concurrency bounds for 8GB system stability
set -gx CARGO_BUILD_JOBS 4
if not set -q NODE_OPTIONS
    set -gx NODE_OPTIONS "--max-old-space-size=1536"
end
