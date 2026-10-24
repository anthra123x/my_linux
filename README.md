# Sistema de Dotfiles y Configuración Personalizada

Repositorio centralizado, modular y sincronizado de configuraciones para **CachyOS / Arch Linux** con **Hyprland**, **Quickshell (Illogical Impulse)**, **Fish Shell**, **Starship**, **Kitty** y **Matugen**.

---

## 📋 Resumen del Entorno

| Componente | Herramienta | Ruta en Sistema |
| :--- | :--- | :--- |
| **Compositor / WM** | Hyprland (Wayland) | `~/.config/hypr/` |
| **Desktop Shell / Barra** | Quickshell (`ii`) | `~/.config/quickshell/` y `~/.config/illogical-impulse/` |
| **Theming Dinámico** | Matugen (Material You) | `~/.config/matugen/` |
| **Shell Principal** | Fish Shell | `~/.config/fish/` |
| **Shells Secundarias** | Bash y Zsh | `~/.bashrc`, `~/.zshrc` |
| **Prompt** | Starship | `~/.config/starship.toml` |
| **Terminales** | Kitty / Ghostty | `~/.config/kitty/`, `~/.config/ghostty/` |
| **Lanzador de Apps** | Fuzzel | `~/.config/fuzzel/` |
| **Menú de Salida** | Wlogout | `~/.config/wlogout/` |
| **Monitor del Sistema** | Btop | `~/.config/btop/` |
| **Visualizador de Audio** | Cava | `~/.config/cava/` |
| **Optimizaciones Sistema** | Variables de entorno | `~/.config/environment.d/` |
| **Servicios y Timers** | Systemd User Units | `~/.config/systemd/user/` |
| **Scripts de Utilidad** | Scripts propios | `~/.local/bin/` |

---

## 📁 Estructura del Repositorio

```text
dotfiles/
├── .config/                # Mapeo exacto 1:1 con ~/.config/
│   ├── hypr/               # Configuración completa de Hyprland (core, custom, themes, scripts)
│   ├── quickshell/         # Widgets de escritorio, paneles, barra y controles (ii)
│   ├── illogical-impulse/  # Ajustes de IA, fuentes y temas del entorno gráfico
│   ├── matugen/            # Generador de paletas Material You desde wallpapers
│   ├── fish/               # Shell interactiva principal (aliases, paths, starship)
│   ├── kitty/              # Configuración y extensiones Python de Kitty
│   ├── ghostty/            # Configuración de Ghostty
│   ├── fuzzel/             # Lanzador rápido de aplicaciones
│   ├── wlogout/            # Pantalla de apagado / reinicio / bloqueo
│   ├── btop/               # Monitor de recursos con temas
│   ├── cava/               # Visualizador de espectro de audio
│   ├── environment.d/      # Ajustes de memoria baja y navegador por defecto
│   ├── systemd/user/       # Servicios de usuario y timers activos
│   ├── gtk-3.0/ & gtk-4.0/ # Estilos e integración GTK
│   ├── xsettingsd/         # Ajustes XSettings para Wayland/XWayland
│   ├── fontconfig/         # Renderizado de fuentes del sistema
│   ├── mpv/                # Reproductor multimedia
│   ├── micro/              # Editor de terminal
│   ├── starship.toml       # Estilo del prompt
│   └── *-flags.conf        # Flags Wayland para navegadores (Brave, Chrome, etc.)
├── home/                   # Ficheros de configuración en el raíz del usuario (~/)
│   ├── .bashrc
│   ├── .bash_profile
│   ├── .bash_logout
│   ├── .zshrc
│   ├── .zshenv
│   ├── .gitconfig
│   └── .vimrc
├── scripts/                # Scripts de mantenimiento en ~/.local/bin/
│   ├── hypr-session-save   # Guardado de sesión Hyprland
│   ├── hypr-session-restore# Restauración de sesión
│   ├── lidwatch            # Gestión de cierre de tapa en laptops
│   ├── stale-process-reaper# Limpieza de procesos huérfanos
│   ├── tmpfs-gc            # Liberación de memoria en /tmp
│   └── fix-laptop-audio.sh # Corrección de audio
├── install.sh              # Script instalador automático con backup
├── sync.sh                 # Sincronizador bidireccional (Sistema -> Repo)
└── .gitignore
```

---

## 🚀 Despliegue e Instalación

### ¿Por qué `cp -r dotfiles/* ~/` no funcionaba antes?
En la organización previa, las carpetas estaban categorizadas como `shell/`, `terminal/`, etc. Al hacer `cp -r dotfiles/* ~/`, se copiaban a directorios incorrectos como `~/shell/` o `~/terminal/` en lugar de `~/.config/kitty/` o `~/.bashrc`. Además, faltaban scripts esenciales y ficheros de Hyprland.

### Métodos de Instalación Disponibles

#### 1. Modo Simbólico (Recomendado)
Crea enlaces simbólicos desde el sistema hacia este repositorio. Cualquier cambio que hagas en tu sistema se refleja instantáneamente en Git:
```bash
./install.sh --symlink
```

#### 2. Modo Copia Directa
Si prefieres copiar físicamente los archivos sin enlazar:
```bash
./install.sh --copy
```

Ambos comandos realizan automáticamente una copia de seguridad en `~/.dotfiles_backup_<FECHA>/` antes de sobreescribir ningún archivo existente.

---

## 🔄 Sincronización Inversa (Sistema ➔ Repositorio)

Cuando personalices tu sistema en vivo (por ejemplo, si añades un nuevo alias en `fish`, cambias un atajo en `hyprland`, o agregas un script):

```bash
# Ver qué archivos cambiaron en tu equipo respecto al repositorio:
./sync.sh --diff

# Traer todos los cambios actualizados del equipo al repositorio:
./sync.sh --pull
```

Una vez ejecutado, los cambios quedarán listos para guardar en Git:
```bash
git add .
git commit -m "feat(config): personalización de tema y atajos"
```

---

## 🎨 Guía de Personalización Rápida

### 1. Atajos de Teclado y Reglas de Ventanas (Hyprland)
Edita las configuraciones de usuario en:
- Atajos adicionales: `.config/hypr/custom/keybinds.lua`
- Variables de entorno: `.config/hypr/custom/env.lua`
- Reglas de ventanas: `.config/hypr/custom/rules.lua`
- Comandos al inicio: `.config/hypr/custom/execs.lua`

### 2. Temas y Paleta de Colores
- **Temas Predefinidos**: Disponibles en `.config/hypr/themes/` (Rosepine, Catppuccin, Tokyo Night, Nord, Oxocarbon, Monokai, etc.).
- **Material You Automático**: Matugen genera paletas armónicas acordes al fondo de pantalla actual mediante `.config/matugen/config.toml`.

### 3. Shell (Fish)
- Edita `.config/fish/config.fish` para añadir aliases, funciones y paths.
- El prompt utiliza Starship (`.config/starship.toml`).

### 4. Terminal (Kitty)
- Configura fuentes, transparencias y atajos en `.config/kitty/kitty.conf`.
