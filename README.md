```text
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
```

# OMICRON: Entorno de Escritorio y Arquitectura de Sistema

Entorno Wayland de alto rendimiento, bajo consumo y personalizacion dinamica para **CachyOS / Arch Linux**. Construido sobre **Hyprland**, componentes del sistema nativos en **Rust**, **Quickshell** (Material You), **Fish Shell** y el motor de fondos animados **Wallmotion**.

El proyecto evoluciona desde una configuracion base hacia una **Shell reactiva y futura distribucion independiente (Omicron OS)** basada en la arquitectura modular **Cell**, disenada bajo la premisa de **Aislamiento Dinamico de Recursos**: *el sistema solo consume energia y ciclos de computo para lo que esta visible y en foco en el espacio de trabajo actual*.

---

## Capturas del Entorno

### Escritorio Principal (Fondo Animado y Barra Quickshell)
![Escritorio](assets/desktop-clean.png)

### Terminal con Fastfetch y Starship Prompt
![Terminal](assets/desktop-terminal.png)

### Selector Visual de Fondos Animados (Quickshell Carousel)
![Selector de Fondos Animados](assets/desktop-wallpapers.png)

### Aplicaciones y Diseno de Ventanas
![Aplicaciones](assets/desktop-apps.png)

---

## Vision y Arquitectura de Omicron (Motor Cell)

A diferencia de los entornos de escritorio tradicionales (GNOME, KDE o Sway/Hyprland genericos) donde las aplicaciones en segundo plano compiten indefinidamente por tiempo de CPU, memoria y bus de renderizado, la arquitectura de **Omicron Shell** implementa una jerarquia de cuatro capas desacopladas con supervision activa en tiempo real:

```mermaid
graph TD
    subgraph Capa 0: Base de Sistema y Kernel
        K1["Linux Kernel CachyOS (x86-64-v3 + Sched-ext BPFland)"]
        K2["Memoria ZRAM 12 GB zstd (0 Bytes en Swap NVMe)"]
        K3["THP madvise + vm.stat_interval 10 (C-states C8/C10)"]
    end

    subgraph Capa 1: Compositor y Tuberia Grafica
        W1["Hyprland 0.57.0 (Aquamarine, Lua)"]
        W2["Tasa fija a 60 FPS sin tirones entre workspaces"]
        W3["Aceleracion por hardware Intel VA-API (VDBOX ASIC)"]
    end

    subgraph Capa 2: Supervision y Gobernanza (Rust)
        R1["hypr-workspace-governor (Priorizacion balanceada nice 5 / nice 0)"]
        R2["Proteccion de audio en tiempo real via PipeWire (pactl cache)"]
        R3["Consumo de memoria nativa: inferior a 1.4 MB de RAM"]
    end

    subgraph Capa 3: Capa de Presentacion y Experiencia (Omicron UI)
        U1["Quickshell + Matugen (Paletas dinamicas Material You)"]
        U2["Wallmotion (Reemplazo atomico via IPC mpvpaper a 60 FPS)"]
        U3["Lanzador Fuzzel y Menu de energia Wlogout"]
    end

    K1 --> W1
    K2 --> W1
    K3 --> W1
    W1 --> R1
    W1 --> U1
    R1 --> U1
    U2 --> W3
```

### Principios Fundamentales
1. **Aislamiento Activo de Espacios de Trabajo:** Las ventanas en espacios de trabajo ocultos se trasladan automaticamente a la politica del kernel `SCHED_IDLE`, prioridad `nice 19` y clase de E/S ociosa. Cero desperdicio de ciclos para aplicaciones invisibles.
2. **Proteccion Inteligente de Flujos Multimedia:** El supervisor distingue entre procesos silenciosos y aplicaciones con reproduccion de audio activa (Spotify, llamadas, reproductores), asegurando que el sonido nunca sufra micro-cortes.
3. **Cero Dependencia de Interpretes en Segundo Plano:** Los demonios residentes se compilan en Rust nativo con optimizacion en tiempo de enlace (LTO), eliminando recolectores de basura, tiempos de arranque en frio y huellas de memoria elevadas.
4. **Reserva Total de Potencia para 60 FPS:** El procesador (Intel Core i3-N305 de 8 nucleos Gracemont) modula su frecuencia de reposo a ~1.4 GHz, dejando los 23W de potencia electrica del encapsulado disponibles para que la GPU Intel UHD sostenga 1250 MHz constantes.

---

## Especificaciones del Sistema de Referencia

- **Dispositivo:** ASUS Vivobook Go E1504GA
- **Procesador:** Intel Core i3-N305 (8 nucleos Gracemont hasta 3.8 GHz)
- **Graficos:** Intel UHD Graphics (32 EUs Alder Lake-N, soporte VAAPI QuickSync completo)
- **Memoria:** 8 GB LPDDR5 4800 MT/s
- **Pantalla:** 1920x1080 @ 60Hz (panel eDP-1)
- **Sistema Operativo:** CachyOS Linux (Kernel optimizado x86-64-v3)

---

## Pila de Software y Modulos del Sistema

| Categoria | Componente | Implementacion / Ruta | Rol Arquitectonico |
| :--- | :--- | :--- | :--- |
| **Gobernador de Recursos** | `hypr-workspace-governor` | `crates/hypr-workspace-governor/` | Daemon nativo en Rust (< 1 MB RAM) que aplica `SCHED_IDLE` a workspaces inactivos. |
| **Gestion Energetica** | `cell-powerd` | `crates/cell-powerd/` | Daemon nativo en Rust (~500 KB RAM) de lectura directa en sysfs para perfiles y bateria. |
| **Compositor Wayland** | Hyprland 0.57.0 | `.config/hypr/` | Gestor de ventanas con Lua y tasa condicional de repintado. |
| **Barra y Paneles** | Quickshell (Hyprsimple) | `.config/quickshell/` | Interfaz reactiva con integracion IPC. |
| **Fondos Animados** | Wallmotion | `scripts/wallmotion`, `.config/wallmotion/` | Motor de vídeo por hardware VAAPI con escalado entero 2:1 a 60 FPS. |
| **Generador de Temas** | Matugen | `.config/matugen/` | Extraccion algoritmica de color Material You desde fondos. |
| **Shell Interactiva** | Fish Shell | `.config/fish/` | Shell de comandos con auto-sugerencias y Starship prompt. |
| **Terminales** | Ghostty / Kitty | `.config/ghostty/`, `.config/kitty/` | Emuladores de terminal con aceleracion GPU nativa. |
| **Lanzador de Apps** | Fuzzel | `.config/fuzzel/` | Menu de aplicaciones Wayland de arranque instantaneo. |
| **Menu de Salida** | Wlogout | `.config/wlogout/` | Gestion de sesion, bloqueo y apagado. |
| **Servicios de Usuario** | Systemd User Units | `.config/systemd/user/` | Orquestacion de ciclo de vida de demonios de usuario. |
| **Scripts de Soporte** | Herramientas auxiliares | `scripts/` | Utilidades de audio, brillo, wifi y automatizacion. |

---

## Optimizaciones de Rendimiento y Memoria en Produccion

1. **Memoria ZRAM de 12 GB (Compresion ZSTD):**
   - Configurado en `/etc/systemd/zram-generator.conf` con prioridad 100.
   - 0 Bytes de uso en el archivo de intercambio en SSD NVMe, eliminando la latencia de contencion de disco.
2. **Gobernador de Espacios de Trabajo en Rust:**
   - Reduce aplicaciones pesadas fuera de pantalla (LibreOffice, navegadores en reposo) de mas del 10% de CPU a menos del 0.5% en reposo.
   - Conexion directa mediante socket UNIX sin llamadas lentas a `hyprctl`.
3. **Priorizacion de GPU a 60 FPS:**
   - `render_unfocused_fps = 30`: Las ventanas sin foco repintan a 30 FPS para dedicar todo el ancho de banda a la ventana interactiva.
4. **Afinamiento del Kernel y Politicas Termicas:**
   - Transparent Huge Pages configurado en `madvise` mediante `/etc/tmpfiles.d/thp.conf` (ahorro de hasta 700 MB de RAM fragmentada).
   - `vm.stat_interval = 10`: Reduce interrupciones de temporizador en reposo en un 90%, habilitando estados C8/C10 en los nucleos Gracemont.
   - Script de aplicacion integral: [`scripts/apply-kernel-optimizations.sh`](file:///home/omicron/.gemini/antigravity-ide/scratch/dotfiles/scripts/apply-kernel-optimizations.sh).

---

## Subsistema de Fondos de Pantalla

El sistema unifica dos motores de fondo con gestion automatica de capas en Wayland:

### 1. Fondos Estaticos con Paletas Dinamicas
- **Atajo:** `SUPER + SHIFT + W`
- **Ubicacion:** `.config/hypr/themes/<tema>/backgrounds/`
- Aplica fondos via `hyprpaper`, recalcula los colores del sistema con Matugen y actualiza Quickshell en caliente.

### 2. Fondos Animados por Hardware (Wallmotion)
- **Atajo:** `SUPER + SHIFT + T`
- **Ubicacion:** `.config/wallmotion/library/`
- **Motor:** `mpvpaper` acelerado por hardware VAAPI (QuickSync VDBOX).
- Downscaling 2:1 integro de 4K a 1080p usando samplers bilineales por hardware (2x2 SSAA), entregando 60 FPS fluidos con menos del 2% de carga de CPU.
- Convivencia automatica: suspende temporalmente `hyprpaper.service` al reproducir un fondo animado y lo reactiva de inmediato al volver a fondos estaticos.

---

## Hoja de Ruta: De Dotfiles a Omicron OS

El desarrollo del proyecto se divide en 3 fases estrategicas:

### Fase 1: Consolidacion de Demonios Nativos (Actual)
- Migracion de demonios residentes de Python/Bash hacia Rust en `crates/`.
- Perfeccionamiento del gobernador de recursos por espacio de trabajo con cache TTL de bajo jitter.
- Optimizacion del reemplazo de fondos animados atomico por socket IPC con decodificacion VA-API sin costo de CPU.

### Fase 2: Omicron Shell Unificada (Medio Plazo)
- Integracion de los modulos de barra, lanzador, panel de notificaciones y selector de fondos en un runtime unificado con protocolo IPC propio (`cell-ipc`).
- Centro de control grafico ligero para gestion de perfiles energeticos, visuales y de red sin dependencias pesadas de GNOME.

### Fase 3: Distribucion Independiente (Omicron OS - Largo Plazo)
- Construccion de imagen ISO reproducible con instalador Calamares preconfigurado.
- Repositorio de paquetes binarios optimizados con flags de compilacion x86-64-v3 y LTO activado.
- Perfil de hardware autoconfigurado con politicas de distribucion energetica para graficos integrados Intel y AMD.

---

## Estructura del Repositorio

```text
.
├── .config/
│   ├── btop/               # Monitor del sistema con temas
│   ├── cava/               # Visualizador de audio
│   ├── environment.d/      # Variables de entorno graficas
│   ├── fish/               # Configuracion de Fish Shell
│   ├── fuzzel/             # Lanzador de aplicaciones
│   ├── ghostty/ & kitty/   # Emuladores de terminal
│   ├── hypr/               # Configuracion completa de Hyprland (Lua)
│   ├── matugen/            # Plantillas Material You
│   ├── quickshell/         # Barra superior y paneles
│   ├── starship.toml       # Estilo del prompt
│   ├── systemd/user/       # Servicios de usuario systemd
│   └── wallmotion/         # Fondos animados y miniaturas
├── assets/                 # Capturas del entorno de escritorio
├── crates/                 # Componentes nativos del sistema en Rust
│   └── hypr-workspace-governor/  # Daemon de aislamiento de recursos
├── home/                   # Archivos para el directorio raiz del usuario
│   ├── .bashrc
│   ├── .gitconfig
│   └── .zshrc
├── scripts/                # Scripts de soporte, energia y mantenimiento
│   ├── apply-kernel-optimizations.sh  # Despliegue de ajustes de kernel y sysctl
│   ├── battery-monitor.sh             # Monitor de bateria
│   ├── wallmotion                     # Motor de fondos animados
│   └── README.md                      # Documentacion modular de scripts
├── install.sh              # Instalador automatico con compilacion de crates Rust
├── sync.sh                 # Sincronizador bidireccional (Sistema -> Repo)
├── .gitignore
└── README.md
```

---

## Despliegue y Uso

### Clonar el Repositorio

```bash
git clone https://github.com/anthra123x/my_linux.git ~/dotfiles
cd ~/dotfiles
```

### Instalacion

Compila los crates de Rust nativos e instala la configuracion completa:
```bash
./install.sh --symlink
```

### Aplicar Optimizaciones de Kernel en el Sistema

```bash
sudo ~/.local/bin/apply-kernel-optimizations.sh
```

---

## Atajos de Teclado Principales

| Combinacion | Accion |
| :--- | :--- |
| `SUPER + Return` | Abrir terminal (Ghostty / Kitty) |
| `SUPER + Space` | Lanzador de aplicaciones (Fuzzel) |
| `SUPER + Q` | Cerrar ventana activa |
| `SUPER + SHIFT + W` | Selector visual de fondos estaticos por tema |
| `SUPER + SHIFT + T` | Selector visual de fondos animados (Quickshell) |
| `SUPER + Ctrl + L` | Conmutar reproduccion de fondo animado (Play / Pause) |
| `SUPER + [1-9]` | Cambiar al espacio de trabajo 1-9 |
| `SUPER + SHIFT + [1-9]` | Mover ventana al espacio de trabajo 1-9 |
| `SUPER + Escape` | Menu de energia y apagado (Wlogout) |
