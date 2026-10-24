#!/usr/bin/env bash
# ==============================================================================
# Script de Sincronización Inversa (Sistema -> Repositorio Dotfiles)
# ==============================================================================
# Lee las rutas de configuración activas del sistema y actualiza el repositorio
# para que los cambios estén listos para ser guardados en Git.
# ==============================================================================

set -eo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GREEN="\033[1;32m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
RESET="\033[0m"

log_info() { echo -e "${BLUE}[INFO]${RESET} $1"; }
log_ok()   { echo -e "${GREEN}[OK]${RESET} $1"; }
log_warn() { echo -e "${YELLOW}[AVISO]${RESET} $1"; }

show_help() {
    cat << EOF
Uso: $0 [OPCIONES]

Opciones:
  --diff     Mostrar diferencias entre el sistema y el repositorio sin copiar.
  --pull     Copiar los cambios del sistema hacia el repositorio (predeterminado).
  -h, --help Mostrar esta ayuda.
EOF
}

DO_DIFF=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --diff) DO_DIFF=true; shift ;;
        --pull) DO_DIFF=false; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "Opción no reconocida: $1"; show_help; exit 1 ;;
    esac
done

sync_folder() {
    local src="$1"
    local dest="$2"
    local exclude_args=("${@:3}")

    if [ ! -d "$src" ]; then
        return
    fi

    mkdir -p "$dest"

    if [ "$DO_DIFF" = true ]; then
        echo -e "${YELLOW}=== Diferencias en $src ===${RESET}"
        diff -u -r --exclude="*.bak*" --exclude="*~" --exclude=".git" "$dest" "$src" || true
    else
        rsync -av --delete "${exclude_args[@]}" "$src/" "$dest/"
    fi
}

sync_file() {
    local src="$1"
    local dest="$2"

    if [ ! -f "$src" ]; then
        return
    fi

    mkdir -p "$(dirname "$dest")"

    if [ "$DO_DIFF" = true ]; then
        if [ -f "$dest" ]; then
            diff -u "$dest" "$src" || true
        else
            echo "Nuevo archivo en el sistema: $src"
        fi
    else
        cp -p "$src" "$dest"
        log_ok "Sincronizado: $(basename "$src")"
    fi
}

log_info "Sincronizando configuraciones del sistema hacia $REPO_DIR..."

# 1. ~/.config
sync_folder "$HOME/.config/hypr" "$REPO_DIR/.config/hypr" --exclude="*.bak*" --exclude="*~"
sync_folder "$HOME/.config/quickshell" "$REPO_DIR/.config/quickshell"
sync_folder "$HOME/.config/illogical-impulse" "$REPO_DIR/.config/illogical-impulse"
sync_folder "$HOME/.config/matugen" "$REPO_DIR/.config/matugen"
sync_folder "$HOME/.config/fish" "$REPO_DIR/.config/fish"
sync_folder "$HOME/.config/kitty" "$REPO_DIR/.config/kitty"
sync_folder "$HOME/.config/ghostty" "$REPO_DIR/.config/ghostty"
sync_folder "$HOME/.config/fuzzel" "$REPO_DIR/.config/fuzzel"
sync_folder "$HOME/.config/wlogout" "$REPO_DIR/.config/wlogout"
sync_folder "$HOME/.config/btop" "$REPO_DIR/.config/btop"
sync_folder "$HOME/.config/cava" "$REPO_DIR/.config/cava"
sync_folder "$HOME/.config/environment.d" "$REPO_DIR/.config/environment.d"
sync_folder "$HOME/.config/gtk-3.0" "$REPO_DIR/.config/gtk-3.0"
sync_folder "$HOME/.config/gtk-4.0" "$REPO_DIR/.config/gtk-4.0"
sync_folder "$HOME/.config/xsettingsd" "$REPO_DIR/.config/xsettingsd"
sync_folder "$HOME/.config/fontconfig" "$REPO_DIR/.config/fontconfig"
sync_folder "$HOME/.config/mpv" "$REPO_DIR/.config/mpv"
sync_folder "$HOME/.config/micro" "$REPO_DIR/.config/micro" --exclude="syntax"
sync_folder "$HOME/.config/systemd/user" "$REPO_DIR/.config/systemd/user" --exclude="plasma-*.service" --exclude="*.wants"

# Ficheros individuales en ~/.config
for f in "$HOME/.config"/*-flags.conf "$HOME/.config/starship.toml" "$HOME/.config/user-dirs.dirs" "$HOME/.config/mimeapps.list"; do
    if [ -f "$f" ]; then
        sync_file "$f" "$REPO_DIR/.config/$(basename "$f")"
    fi
done

# 2. Home root
for f in .bashrc .bash_profile .bash_logout .zshrc .zshenv .gitconfig .vimrc; do
    if [ -f "$HOME/$f" ]; then
        sync_file "$HOME/$f" "$REPO_DIR/home/$f"
    fi
done

# 3. Scripts del sistema
for s in hypr-session-save hypr-session-restore lidwatch stale-process-reaper tmpfs-gc fix-laptop-audio.sh fix-oom-and-restore.sh fix-greeter-wallpaper.sh greeter-migrate-tuigreet.sh opencode-browser-gc; do
    if [ -f "$HOME/.local/bin/$s" ]; then
        sync_file "$HOME/.local/bin/$s" "$REPO_DIR/scripts/$s"
        chmod +x "$REPO_DIR/scripts/$s"
    fi
done

log_ok "Sincronización completada con éxito."
