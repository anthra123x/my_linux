#!/usr/bin/env bash
# check-gamepad.sh
# Verificación y diagnóstico de mandos inalámbricos (Bluetooth / USB)

set -euo pipefail

COLOR_RESET="\033[0m"
COLOR_GREEN="\033[1;32m"
COLOR_YELLOW="\033[1;33m"
COLOR_CYAN="\033[1;36m"
COLOR_RED="\033[1;31m"

echo -e "${COLOR_CYAN}====================================================${COLOR_RESET}"
echo -e "${COLOR_CYAN}        DIAGNÓSTICO DE CONTROL INALÁMBRICO         ${COLOR_RESET}"
echo -e "${COLOR_CYAN}====================================================${COLOR_RESET}"

# 1. Estado de Kernel y Controladores
echo -e "\n${COLOR_YELLOW}[1/4] Controladores del Kernel:${COLOR_RESET}"
for mod in hid_playstation hid_sony joydev uinput hidp; do
    normalized="${mod//-/_}"
    if lsmod | awk '{print $1}' | grep -qx "$normalized"; then
        echo -e "  - Módulo $mod: ${COLOR_GREEN}Cargado [OK]${COLOR_RESET}"
    else
        echo -e "  - Módulo $mod: ${COLOR_YELLOW}No cargado (disponible bajo demanda)${COLOR_RESET}"
    fi
done

ertm=$(cat /sys/module/bluetooth/parameters/disable_ertm 2>/dev/null || echo "N")
if [ "$ertm" = "Y" ]; then
    echo -e "  - Parámetro disable_ertm: ${COLOR_GREEN}Activo (Y) [OK para mandos]${COLOR_RESET}"
else
    echo -e "  - Parámetro disable_ertm: ${COLOR_YELLOW}Inactivo (N)${COLOR_RESET}"
fi

# 2. Configuración de BlueZ (input.conf)
echo -e "\n${COLOR_YELLOW}[2/4] Configuración de Bluetooth (BlueZ):${COLOR_RESET}"
if grep -q "UserspaceHID\s*=\s*false" /etc/bluetooth/input.conf 2>/dev/null; then
    echo -e "  - UserspaceHID=false: ${COLOR_GREEN}Correcto (usa HID del kernel) [OK]${COLOR_RESET}"
else
    echo -e "  - UserspaceHID: ${COLOR_RED}No optimizado para DualShock/mandos${COLOR_RESET}"
fi

if grep -q "ClassicBondedOnly\s*=\s*false" /etc/bluetooth/input.conf 2>/dev/null; then
    echo -e "  - ClassicBondedOnly=false: ${COLOR_GREEN}Correcto (permite conexión inmediata) [OK]${COLOR_RESET}"
else
    echo -e "  - ClassicBondedOnly: ${COLOR_YELLOW}No configurado${COLOR_RESET}"
fi

# 3. Dispositivos Bluetooth Registrados
echo -e "\n${COLOR_YELLOW}[3/4] Mandos Bluetooth vinculados:${COLOR_RESET}"
known_controllers=$(bluetoothctl devices | grep -iE 'controller|gamepad|xbox|sony|wireless' || true)
if [ -n "$known_controllers" ]; then
    echo "$known_controllers" | while read -r line; do
        dev_mac=$(echo "$line" | awk '{print $2}')
        dev_name=$(echo "$line" | cut -d' ' -f3-)
        is_connected=$(bluetoothctl info "$dev_mac" | awk '/Connected:/{print $2}')
        if [ "$is_connected" = "yes" ]; then
            echo -e "  - $dev_name ($dev_mac): ${COLOR_GREEN}CONECTADO${COLOR_RESET}"
        else
            echo -e "  - $dev_name ($dev_mac): ${COLOR_YELLOW}Desconectado / En espera${COLOR_RESET}"
        fi
    done
else
    echo -e "  ${COLOR_YELLOW}No se encontraron mandos emparejados previamente.${COLOR_RESET}"
fi

# 4. Dispositivos de Entrada Detectados (/dev/input)
echo -e "\n${COLOR_YELLOW}[4/4] Detección en el Sistema (/dev/input):${COLOR_RESET}"
js_found=false
for js in /dev/input/js*; do
    if [ -e "$js" ]; then
        js_name=$(cat "/sys/class/input/${js#/dev/input/}/device/name" 2>/dev/null || echo "Desconocido")
        echo -e "  - ${COLOR_GREEN}Mando detectado:${COLOR_RESET} $js ($js_name)"
        js_found=true
    fi
done

if [ "$js_found" = true ]; then
    echo -e "\n${COLOR_GREEN}¡Éxito! El sistema detecta el mando para juegos (Steam, emuladores y juegos nativos).${COLOR_RESET}"
else
    echo -e "  ${COLOR_RED}No hay mandos conectados actualmente.${COLOR_RESET}"
    echo -e "\n${COLOR_CYAN}--- CÓMO CONECTARLO / VINCULARLO ---${COLOR_RESET}"
    echo -e "1. Si es mando de ${COLOR_YELLOW}PlayStation (DualShock 4 / PS4)${COLOR_RESET}:"
    echo -e "   - Con el mando apagado, mantén presionado ${COLOR_GREEN}SHARE + botón PS${COLOR_RESET} durante 3-5 segundos."
    echo -e "   - La barra de luz comenzará a parpadear rápidamente con un doble destello blanco continuo."
    echo -e "2. Si ya está emparejado:"
    echo -e "   - Solo presiona el ${COLOR_GREEN}botón PS${COLOR_RESET} una vez para que se reconecte automáticamente."
    echo -e "3. Si es mando de ${COLOR_YELLOW}Xbox${COLOR_RESET}:"
    echo -e "   - Mantén presionado el botón pequeño de sincronización superior hasta que el logo parpadee rápido."
fi
echo -e "${COLOR_CYAN}====================================================${COLOR_RESET}"
