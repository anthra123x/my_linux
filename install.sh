#!/usr/bin/env bash
# ==============================================================================
# Script de Instalación y Despliegue de Dotfiles
# ==============================================================================
# Soporta:
#   - Modo Enlaces Simbólicos (symlinks - Recomendado para desarrollo en vivo)
#   - Modo Copia directa (copy - Copia los ficheros a ~/.config, ~/, ~/.local/bin)
#   - Backup automático de configuraciones existentes
# ==============================================================================

set -eo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles_backup_$(date +%Y%m%d_%H%M%S)"
MODE="symlink" # 'symlink' o 'copy'
DO_BACKUP=true

# Colores para salida de terminal
GREEN="\033[1;32m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

log_info() { echo -e "${BLUE}[INFO]${RESET} $1"; }
log_ok()   { echo -e "${GREEN}[OK]${RESET} $1"; }
log_warn() { echo -e "${YELLOW}[AVISO]${RESET} $1"; }
log_err()  { echo -e "${RED}[ERROR]${RESET} $1"; }

show_help() {
    cat << EOF
Uso: $0 [OPCIONES]

Opciones:
  -s, --symlink    Instalar mediante enlaces simbólicos (predeterminado).
  -c, --copy       Instalar mediante copia directa de archivos.
  --no-backup      No crear copia de seguridad de las configuraciones actuales.
  -h, --help       Mostrar esta ayuda.

Ejemplo:
  $0 --symlink
  $0 --copy
EOF
}

# Parsear argumentos
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--symlink) MODE="symlink"; shift ;;
        -c|--copy)    MODE="copy"; shift ;;
        --no-backup)  DO_BACKUP=false; shift ;;
        -h|--help)    show_help; exit 0 ;;
        *) log_err "Opción desconocida: $1"; show_help; exit 1 ;;
    esac
done

echo -e "${BLUE}=====================================================${RESET}"
echo -e "${GREEN}   Instalador de Dotfiles del Sistema (CachyOS/Hyprland)${RESET}"
echo -e "${BLUE}=====================================================${RESET}"
log_info "Directorio de origen: $REPO_DIR"
log_info "Modo seleccionado: $MODE"

# 1. Crear directorios base necesarios en el destino
mkdir -p "$HOME/.config" "$HOME/.local/bin"

# 2. Función de instalación de un elemento (archivo o carpeta)
install_item() {
    local src="$1"
    local dest="$2"

    if [ ! -e "$src" ]; then
        return
    fi

    # Si el destino ya existe y no apunta ya al origen
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        if [ "$MODE" = "symlink" ] && [ -L "$dest" ] && [ "$(readlink -f "$dest")" = "$(readlink -f "$src")" ]; then
            log_ok "Ya enlazado: $dest -> $src"
            return
        fi

        if [ "$DO_BACKUP" = true ]; then
            mkdir -p "$BACKUP_DIR"
            local rel_path="${dest#$HOME/}"
            local target_bak="$BACKUP_DIR/$rel_path"
            mkdir -p "$(dirname "$target_bak")"
            cp -rP "$dest" "$target_bak" 2>/dev/null || true
            log_warn "Backup creado para: $dest -> $target_bak"
        fi
        rm -rf "$dest"
    fi

    mkdir -p "$(dirname "$dest")"

    if [ "$MODE" = "symlink" ]; then
        ln -sf "$src" "$dest"
        log_ok "Enlace creado: $dest -> $src"
    else
        cp -rP "$src" "$dest"
        log_ok "Copiado: $dest"
    fi
}

# 3. Instalar aplicaciones y configuraciones en ~/.config
log_info "--- Desplegando archivos en ~/.config ---"
for item in "$REPO_DIR/.config"/*; do
    if [ -e "$item" ]; then
        base="$(basename "$item")"
        install_item "$item" "$HOME/.config/$base"
    fi
done

# 4. Instalar ficheros raíz de Home (bash, zsh, git, vim)
log_info "--- Desplegando archivos de entorno en ~/ ---"
if [ -d "$REPO_DIR/home" ]; then
    for item in "$REPO_DIR/home"/.[!.]* "$REPO_DIR/home"/*; do
        if [ -e "$item" ]; then
            base="$(basename "$item")"
            # Omitir comodín no expandido
            [ "$base" = "*" ] && continue
            install_item "$item" "$HOME/$base"
        fi
    done
fi

# 5. Instalar scripts en ~/.local/bin
log_info "--- Desplegando scripts en ~/.local/bin ---"
if [ -d "$REPO_DIR/scripts" ]; then
    for script in "$REPO_DIR/scripts"/*; do
        if [ -f "$script" ]; then
            base="$(basename "$script")"
            chmod +x "$script"
            install_item "$script" "$HOME/.local/bin/$base"
            chmod +x "$HOME/.local/bin/$base"
        fi
    done
fi

# 6. Recargar systemd de usuario si hay cambios
if command -v systemctl >/dev/null 2>&1; then
    log_info "Recargando demonio systemd de usuario..."
    systemctl --user daemon-reload 2>/dev/null || true
fi

echo -e "${BLUE}=====================================================${RESET}"
log_ok "Instalación completada exitosamente en modo: $MODE."
if [ "$DO_BACKUP" = true ] && [ -d "$BACKUP_DIR" ]; then
    log_info "Copia de respaldo guardada en: $BACKUP_DIR"
fi
echo -e "${BLUE}=====================================================${RESET}"
