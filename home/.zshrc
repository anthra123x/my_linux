source /usr/share/cachyos-zsh-config/cachyos-config.zsh

# OpenCode global tools (ECC and bundled Node runtime)
case ":$PATH:" in
  *:"$HOME/.config/opencode/bin":*) ;;
  *) export PATH="$HOME/.config/opencode/bin:$PATH" ;;
esac



# Added by Antigravity CLI installer
export PATH="/home/omicron/.local/bin:$PATH"
