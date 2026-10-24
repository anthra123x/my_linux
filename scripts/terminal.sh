#!/bin/bash
#
# terminal.sh — detect the user's login shell and wire up the matching
# hyprsimple shell-init script into the correct rc file.
#
# Note: terminals don't have their own shell; they launch the user's *login
# shell* (from /etc/passwd). So we key off that, not $SHELL (which can be
# stale or inherited from a parent process).
#
#   bash → ~/.bashrc                    sources ~/.local/bin/bashrc.sh
#   zsh  → ~/.zshrc                     sources ~/.local/bin/zsh.sh
#   fish → ~/.config/fish/config.fish   sources ~/.local/bin/fish.fish
#
# Idempotent: safe to run multiple times. Can be run standalone or from install.sh.

set -euo pipefail

BIN_DIR="$HOME/.local/bin"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Detect the LOGIN shell (what terminal emulators actually launch).
login_shell="$(getent passwd "$(id -un)" | cut -d: -f7)"
shell_name="$(basename "$login_shell")"

case "$shell_name" in
  bash) rc="$HOME/.bashrc";                   script="$BIN_DIR/bashrc.sh" ;;
  zsh)  rc="$HOME/.zshrc";                    script="$BIN_DIR/zsh.sh"    ;;
  fish) rc="$HOME/.config/fish/config.fish";  script="$BIN_DIR/fish.fish" ;;
  *)
    echo -e "${YELLOW}Unknown login shell '$shell_name' — skipping shell integration.${NC}"
    echo -e "${YELLOW}To set it up manually, source one of:${NC}"
    echo -e "${YELLOW}  $BIN_DIR/{bashrc.sh,zsh.sh,fish.fish}${NC}"
    exit 0
    ;;
esac

echo -e "${GREEN}Detected login shell: ${shell_name}${NC}"

# The matching script must exist before we point an rc file at it.
if [[ ! -f "$script" ]]; then
  echo -e "${RED}Expected script not found: $script${NC}"
  echo -e "${RED}Run the script-copy step first. Skipping shell integration.${NC}"
  exit 1
fi

# Write the ~-relative form so the rc stays portable/readable.
source_line="source ${script/#$HOME/\~}"

mkdir -p "$(dirname "$rc")"
touch "$rc"

if grep -qsF "$(basename "$script")" "$rc"; then
  echo -e "${GREEN}Already wired up in ${rc} — nothing to do.${NC}"
else
  {
    echo ""
    echo "# hyprsimple shell init (added by terminal.sh)"
    echo "$source_line"
  } >> "$rc"
  echo -e "${GREEN}Wired ${source_line} into ${rc}${NC}"
fi
