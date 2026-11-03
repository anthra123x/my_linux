# Modulo: packages

Manifiestos modulares de dependencias de sistema y paquetes para la instalacion de Omicron Shell.

---

## 1. Proposito y Alcance
Centralizar las listas de paquetes del sistema por dominios funcionales (core, interfaz, audio/energia, herramientas CLI y dependencias de compilacion Rust).
Permite al instalador interactivo `install.sh` y a sistemas automatizados resolver, verificar e instalar los paquetes necesarios tanto desde repositorios oficiales de Arch Linux / CachyOS como desde el repositorio AUR.

---

## 2. Contratos
- **Formato:** Un nombre de paquete por linea en texto plano (`.txt`).
- **Comentarios:** Lineas iniciadas con `#` se ignoran.
- **Interaccion con gestores de paquetes:**
  - El instalador concatena los archivos seleccionados.
  - Verifica si el paquete esta instalado localmente mediante `pacman -Qi <pkg>`.
  - Instala paquetes no presentes usando `paru` (prioridad 1), `yay` (prioridad 2) o `sudo pacman -S --needed` (prioridad 3).

---

## 3. Dependencias
- **Gestores soportados:** `pacman`, `paru`, `yay`.
- **Compatibilidad de distros:** Arch Linux, CachyOS, EndeavourOS, Manjaro.

---

## 4. Mapa de Archivos
- `core.txt`: Compositor Wayland Hyprland, demonios de bloqueo/reposo, portales XDG y gestor de sesiones UWSM.
- `ui.txt`: Componentes de interfaz (Quickshell, Matugen, Fuzzel, Wlogout, Mpvpaper y MPV).
- `audio.txt`: Servidor PipeWire, WirePlumber, librerias PulseAudio, brillo y demonio de perfiles energeticos.
- `tools.txt`: Terminal Kitty, Fish Shell, Starship, Fastfetch, Eza, Btop, Cava, Yazi, Zenity y utilidades de portapapeles.
- `dev.txt`: Cadena de herramientas Rust (`cargo`, `rustc`), `base-devel`, Git y `pkg-config`.

---

## 5. Decisiones y Gotchas
1. **Separacion de AUR vs Oficiales:** Algunos paquetes como `quickshell` y `matugen-bin` residen en AUR o en los repositorios especificos de CachyOS. El instalador usa preferentemente un helper AUR (`paru` o `yay`) para resolver ambos origenes sin requerir intervencion manual.
2. **Idempotencia:** Los manifiestos solo declaran requerimientos. El instalador nunca reinstala paquetes ya presentes a menos que se fuerce explicitamente.

---

## 6. Como Verificar
```bash
# Validar sintaxis y paquetes faltantes en el sistema actual
for f in packages/*.txt; do
    echo "Verificando $f..."
    while read -r pkg; do
        [[ -z "$pkg" || "$pkg" =~ ^# ]] && continue
        pacman -Qi "$pkg" >/dev/null 2>&1 || echo "  [FALTA] $pkg"
    done < "$f"
done
```
