#!/usr/bin/env bash
# ==============================================================================
# OMICRON SHELL - Instalador Universal y Gestor de Despliegue
# ==============================================================================
# Plataforma : Arch Linux / CachyOS / EndeavourOS (Wayland / Hyprland)
# Repositorio: https://github.com/anthra123x/my_linux.git
# ==============================================================================

set -eo pipefail

REPO_URL="https://github.com/anthra123x/my_linux.git"
DEFAULT_TARGET="$HOME/.dotfiles"

# Colores ANSI para terminal
CYAN="\033[1;36m"
GREEN="\033[1;32m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
BOLD="\033[1m"
RESET="\033[0m"

log_info()  { echo -e "${BLUE}[INFO]${RESET} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${RESET} $1"; }
log_warn()  { echo -e "${YELLOW}[AVISO]${RESET} $1"; }
log_err()   { echo -e "${RED}[ERROR]${RESET} $1"; }
log_step()  { echo -e "\n${CYAN}==>${RESET} ${BOLD}$1${RESET}"; }

# Banner de arquitectura bare-metal de Omicron
print_banner() {
    cat << 'EOF'
       |  |  |  |  |  |  |
    .--+--+--+--+--+--+--+--.
    |  :  :  :  :  :  :  :  |        ____  __  __ ___ ____ ____   ___  _   _ 
 ---+  [o]   OMICRON        +---    / __ \/  |/  /  _/ ____/ __ \/ __ \/ | / /
 ---+  .-----------------.  +---   / / / / /|_/ // // /   / /_/ / / / /  |/ / 
 ---+  |   >_ fn main()  |  +---  / /_/ / /  / // // /___/ _, _/ /_/ / /|  /  
 ---+  |   {             |  +---  \____/_/  /_/___/\____/_/ |_|\____/_/ |_/   
 ---+  |     sys.init(); |  +---
 ---+  |     *ptr = 0x0; |  +---  ==============================================
 ---+  |   }             |  +---   B A R E - M E T A L   L I N U X   S H E L L
 ---+  .-----------------.  +---   Architecture: CachyOS x86_64 // Hyprland 0.57
 ---+   ARCH: x86_64 // RS  +---   Core Daemons: Rust v2.1 Native Engine
    |  :  :  :  :  :  :  :  |     ==============================================
    '--+--+--+--+--+--+--+--'
       |  |  |  |  |  |  |
EOF
}

# 1. Autodespliegue si se ejecuta directamente a traves de curl / pipe
SELF_SCRIPT="${BASH_SOURCE[0]:-$0}"
if [ ! -f "$SELF_SCRIPT" ] || [ ! -d "$(dirname "$SELF_SCRIPT")/.git" ]; then
    print_banner
    log_info "Instalador invocado remotamente o fuera del arbol git."
    if [ ! -d "$DEFAULT_TARGET" ]; then
        log_info "Clonando repositorio en $DEFAULT_TARGET..."
        if ! command -v git >/dev/null 2>&1; then
            log_err "Git no esta instalado en el sistema. Instala git primero (sudo pacman -S git)."
            exit 1
        fi
        git clone "$REPO_URL" "$DEFAULT_TARGET"
    else
        log_info "Repositorio encontrado en $DEFAULT_TARGET. Actualizando..."
        (cd "$DEFAULT_TARGET" && git pull -q origin main) || true
    fi
    exec bash "$DEFAULT_TARGET/install.sh" "$@"
fi

REPO_DIR="$(cd "$(dirname "$SELF_SCRIPT")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles_backup_$(date +%Y%m%d_%H%M%S)"

# Opciones por defecto
MODE="symlink"
DO_BACKUP=true
DO_DEPS=false
DO_CONFIG=true
DO_RUST=true
DO_SERVICES=true
DO_KERNEL=false
INTERACTIVE=false

show_help() {
    print_banner
    cat << EOF
Uso: $0 [OPCIONES]

Instalador modular para desplegar Omicron Shell en cualquier equipo Arch Linux / CachyOS.

Opciones de despliegue:
  -s, --symlink      Desplegar mediante enlaces simbolicos (predeterminado).
  -c, --copy         Desplegar mediante copia fisica directa de archivos.
  --no-backup        Omitir creacion de respaldo de archivos existentes.

Modos de instalacion:
  -a, --all          Instalacion completa (dependencias, configuraciones, Rust y servicios).
  -i, --interactive  Modo interactivo paso a paso guiado por preguntas.
  --deps             Instalar unicamente dependencias del sistema y AUR.
  --no-deps          Omitir instalacion de dependencias.
  --config-only      Desplegar unicamente archivos de configuracion (.config, ~, scripts).
  --rust-only        Compilar e instalar unicamente demonios nativos de Rust.
  --services-only    Habilitar e iniciar unicamente los servicios systemd de usuario.
  --kernel           Ejecutar script de optimizacion de kernel y memoria con sudo.
  -h, --help         Mostrar esta ayuda.

Ejemplos:
  $0                 Despliegue estandar (symlinks + Rust + servicios).
  $0 --all           Instalacion completa desde cero en un nuevo equipo.
  $0 --interactive   Instalacion guiada personalizada.
EOF
}

# Si no se pasan argumentos y la sesion es interactiva en TTY
if [ $# -eq 0 ] && [ -t 0 ]; then
    INTERACTIVE=true
fi

# Parsear parametros
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--symlink)      MODE="symlink"; shift ;;
        -c|--copy)         MODE="copy"; shift ;;
        --no-backup)       DO_BACKUP=false; shift ;;
        -a|--all)          DO_DEPS=true; DO_CONFIG=true; DO_RUST=true; DO_SERVICES=true; DO_KERNEL=true; INTERACTIVE=false; shift ;;
        -i|--interactive)  INTERACTIVE=true; shift ;;
        --deps)            DO_DEPS=true; DO_CONFIG=false; DO_RUST=false; DO_SERVICES=false; shift ;;
        --no-deps)         DO_DEPS=false; shift ;;
        --config-only)     DO_DEPS=false; DO_CONFIG=true; DO_RUST=false; DO_SERVICES=false; shift ;;
        --rust-only)       DO_DEPS=false; DO_CONFIG=false; DO_RUST=true; DO_SERVICES=false; shift ;;
        --services-only)   DO_DEPS=false; DO_CONFIG=false; DO_RUST=false; DO_SERVICES=true; shift ;;
        --kernel)          DO_KERNEL=true; shift ;;
        -h|--help)         show_help; exit 0 ;;
        *)                 log_err "Opcion no reconocida: $1"; show_help; exit 1 ;;
    esac
done

print_banner

# Asistente interactivo
if [ "$INTERACTIVE" = true ]; then
    echo -e "${BOLD}Bienvenido al instalador de Omicron Shell.${RESET}\n"
    
    read -rp "1. Deseas verificar e instalar dependencias del sistema (pacman/AUR)? [s/N]: " resp_deps
    if [[ "$resp_deps" =~ ^[sS]$ ]]; then
        DO_DEPS=true
    fi

    echo -e "\n2. Metodo de despliegue de archivos de configuracion:"
    echo "   [1] Enlaces simbolicos (Recomendado: las ediciones en git se reflejan en vivo)"
    echo "   [2] Copia fisica directa"
    read -rp "Selecciona opcion [1/2, default 1]: " resp_mode
    if [ "$resp_mode" = "2" ]; then
        MODE="copy"
    else
        MODE="symlink"
    fi

    read -rp $'\n3. Deseas compilar e instalar los demonios nativos de Rust (governor, cell-powerd)? [S/n]: ' resp_rust
    if [[ "$resp_rust" =~ ^[nN]$ ]]; then
        DO_RUST=false
    fi

    read -rp $'\n4. Deseas activar y arrancar los servicios de usuario de systemd? [S/n]: ' resp_services
    if [[ "$resp_services" =~ ^[nN]$ ]]; then
        DO_SERVICES=false
    fi

    read -rp $'\n5. Deseas aplicar las optimizaciones de kernel y memoria (requiere sudo)? [s/N]: ' resp_kernel
    if [[ "$resp_kernel" =~ ^[sS]$ ]]; then
        DO_KERNEL=true
    fi
    echo ""
fi

# Detectar gestor de paquetes de Arch
detect_pkg_manager() {
    if command -v paru >/dev/null 2>&1; then
        echo "paru"
    elif command -v yay >/dev/null 2>&1; then
        echo "yay"
    elif command -v pacman >/dev/null 2>&1; then
        echo "pacman"
    else
        echo ""
    fi
}

# 1. Instalacion de dependencias
if [ "$DO_DEPS" = true ]; then
    log_step "Fase 1: Instalacion de Dependencias del Sistema"
    PKG_MGR=$(detect_pkg_manager)

    if [ -z "$PKG_MGR" ]; then
        log_warn "No se detecto un gestor de paquetes Arch (pacman/paru/yay). Omitiendo instalacion automatica."
    else
        log_info "Gestor de paquetes detectado: $PKG_MGR"
        ALL_PACKAGES=()

        if [ -d "$REPO_DIR/packages" ]; then
            for manifest in "$REPO_DIR/packages"/*.txt; do
                if [ -f "$manifest" ]; then
                    while read -r pkg; do
                        [[ -z "$pkg" || "$pkg" =~ ^# ]] && continue
                        ALL_PACKAGES+=("$pkg")
                    done < "$manifest"
                fi
            done
        fi

        MISSING_PKGS=()
        for pkg in "${ALL_PACKAGES[@]}"; do
            if ! pacman -Qi "$pkg" >/dev/null 2>&1; then
                MISSING_PKGS+=("$pkg")
            fi
        done

        if [ ${#MISSING_PKGS[@]} -eq 0 ]; then
            log_ok "Todos los paquetes declarados ya estan instalados."
        else
            log_info "Paquetes a instalar (${#MISSING_PKGS[@]}): ${MISSING_PKGS[*]}"
            if [ "$PKG_MGR" = "pacman" ]; then
                sudo pacman -S --needed --noconfirm "${MISSING_PKGS[@]}" || log_warn "Algunos paquetes de AUR requieren paru o yay."
            else
                "$PKG_MGR" -S --needed --noconfirm "${MISSING_PKGS[@]}"
            fi
            log_ok "Fase de dependencias completada."
        fi
    fi
fi

# 2. Despliegue de configuraciones y dotfiles
install_file_item() {
    local src="$1"
    local dest="$2"

    [ -e "$src" ] || return 0

    if [ -e "$dest" ] || [ -L "$dest" ]; then
        if [ "$MODE" = "symlink" ] && [ -L "$dest" ] && [ "$(readlink -f "$dest")" = "$(readlink -f "$src")" ]; then
            return 0
        fi

        if [ "$DO_BACKUP" = true ]; then
            mkdir -p "$BACKUP_DIR"
            local rel_path="${dest#$HOME/}"
            local target_bak="$BACKUP_DIR/$rel_path"
            mkdir -p "$(dirname "$target_bak")"
            cp -rP "$dest" "$target_bak" 2>/dev/null || true
        fi
        rm -rf "$dest"
    fi

    mkdir -p "$(dirname "$dest")"

    if [ "$MODE" = "symlink" ]; then
        ln -sf "$src" "$dest"
    else
        cp -rP "$src" "$dest"
    fi
}

if [ "$DO_CONFIG" = true ]; then
    log_step "Fase 2: Despliegue de Configuraciones (Modo: $MODE)"
    mkdir -p "$HOME/.config" "$HOME/.local/bin" "$HOME/.local/share"

    # 2.1 Desplegar ~/.config
    log_info "Instalando modulos en ~/.config..."
    for item in "$REPO_DIR/.config"/*; do
        if [ -e "$item" ]; then
            base="$(basename "$item")"
            install_file_item "$item" "$HOME/.config/$base"
        fi
    done
    log_ok "Configuraciones en ~/.config sincronizadas."

    # 2.2 Desplegar ~/home en $HOME
    if [ -d "$REPO_DIR/home" ]; then
        log_info "Instalando archivos de entorno en ~/..."
        for item in "$REPO_DIR/home"/.[!.]* "$REPO_DIR/home"/*; do
            if [ -e "$item" ]; then
                base="$(basename "$item")"
                [ "$base" = "*" ] && continue
                install_file_item "$item" "$HOME/$base"
            fi
        done
        log_ok "Archivos de entorno de usuario sincronizados."
    fi

    # 2.3 Desplegar scripts en ~/.local/bin
    if [ -d "$REPO_DIR/scripts" ]; then
        log_info "Instalando utilidades y scripts en ~/.local/bin..."
        for script in "$REPO_DIR/scripts"/*; do
            if [ -f "$script" ]; then
                base="$(basename "$script")"
                chmod +x "$script"
                install_file_item "$script" "$HOME/.local/bin/$base"
                chmod +x "$HOME/.local/bin/$base"
            fi
        done
        log_ok "Scripts ejecutables instalados en ~/.local/bin."
    fi

    # Asegurar libreria y thumbs de wallmotion
    mkdir -p "$HOME/.config/wallmotion/library" "$HOME/.config/wallmotion/thumbs"
    if [ -d "$REPO_DIR/.config/wallmotion/library" ]; then
        cp -rn "$REPO_DIR/.config/wallmotion/library"/* "$HOME/.config/wallmotion/library/" 2>/dev/null || true
        cp -rn "$REPO_DIR/.config/wallmotion/thumbs"/* "$HOME/.config/wallmotion/thumbs/" 2>/dev/null || true
    fi

    # Registrar sesion de escritorio Omicron DE
    if [ -f "$REPO_DIR/assets/sessions/omicron.desktop" ]; then
        if [ "$(id -u)" = "0" ]; then
            cp -f "$REPO_DIR/assets/sessions/omicron.desktop" /usr/share/wayland-sessions/ 2>/dev/null || true
        elif sudo -n true 2>/dev/null; then
            sudo cp -f "$REPO_DIR/assets/sessions/omicron.desktop" /usr/share/wayland-sessions/ 2>/dev/null || true
        fi
    fi
fi

# 3. Compilacion e instalacion de demonios de Rust
if [ "$DO_RUST" = true ]; then
    log_step "Fase 3: Compilacion de Motores Nativos de Rust"
    if ! command -v cargo >/dev/null 2>&1; then
        log_warn "Cargo/Rust no esta instalado. Omitiendo compilacion de crates nativos."
    elif [ -d "$REPO_DIR/crates" ]; then
        for crate_dir in "$REPO_DIR/crates"/*; do
            if [ -f "$crate_dir/Cargo.toml" ]; then
                cname="$(basename "$crate_dir")"
                log_info "Compilando $cname en modo release optimizado..."
                (cd "$crate_dir" && cargo build --release -q) || {
                    log_err "Error al compilar $cname. Revisa dependencias de compilacion."
                    continue
                }
                if [ -f "$crate_dir/target/release/$cname" ]; then
                    install -m 755 "$crate_dir/target/release/$cname" "$HOME/.local/bin/$cname"
                    log_ok "Binario instalado: $HOME/.local/bin/$cname"
                fi
            fi
        done
    fi
fi

# 4. Configuracion de servicios systemd de usuario
if [ "$DO_SERVICES" = true ]; then
    log_step "Fase 4: Configuracion de Servicios Systemd de Usuario"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user daemon-reload || true

        SERVICES=(
            "hypr-workspace-governor.service"
            "cell-powerd.service"
            "opencode-browser-gc.timer"
            "stale-process-reaper.timer"
            "tmpfs-gc.timer"
            "hypr-session-save.timer"
        )

        for s in "${SERVICES[@]}"; do
            if [ -f "$HOME/.config/systemd/user/$s" ]; then
                systemctl --user enable "$s" 2>/dev/null || true
                systemctl --user restart "$s" 2>/dev/null || true
                log_ok "Servicio activo: $s"
            fi
        done
    fi
fi

# 5. Optimizaciones de kernel y memoria (opcional)
if [ "$DO_KERNEL" = true ]; then
    log_step "Fase 5: Optimizaciones de Kernel y Memoria"
    KERNEL_SCRIPT="$HOME/.local/bin/apply-kernel-optimizations.sh"
    if [ -x "$KERNEL_SCRIPT" ]; then
        log_info "Ejecutando script de kernel (se solicitara contrasena de sudo si aplica)..."
        sudo "$KERNEL_SCRIPT" || log_warn "No se pudo aplicar la optimizacion de kernel completa."
    fi
fi

echo -e "\n${CYAN}=====================================================${RESET}"
log_ok "Instalacion y configuracion de Omicron Shell completada."
if [ "$DO_BACKUP" = true ] && [ -d "$BACKUP_DIR" ]; then
    log_info "Respaldo previo de configuraciones guardado en:"
    echo "  $BACKUP_DIR"
fi
echo -e "${CYAN}=====================================================${RESET}"
echo -e "Para iniciar la sesion en cualquier momento:"
echo -e "  - En display manager: Selecciona ${BOLD}Hyprland${RESET}"
echo -e "  - En TTY: Ejecuta ${BOLD}uwsm start hyprland.desktop${RESET} o ${BOLD}Hyprland${RESET}\n"
