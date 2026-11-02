#!/usr/bin/env python3
"""
pair-gamepad.py
Asistente interactivo y automático para emparejar mandos Bluetooth (DualShock 4, DualSense, Xbox, etc.)
Detecta el mando cuando se pone en modo emparejamiento, lo vincula con una clave limpia, lo marca como de confianza (trusted)
y verifica que se cree el dispositivo de juego (/dev/input/js0).
"""

import sys
import time
import os
import glob
import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib

AGENT_PATH = "/test/agent"

class AutoAgent(dbus.service.Object):
    @dbus.service.method("org.bluez.Agent1", in_signature="", out_signature="")
    def Release(self):
        pass

    @dbus.service.method("org.bluez.Agent1", in_signature="os", out_signature="")
    def AuthorizeService(self, device, uuid):
        return

    @dbus.service.method("org.bluez.Agent1", in_signature="o", out_signature="s")
    def RequestPinCode(self, device):
        return "0000"

    @dbus.service.method("org.bluez.Agent1", in_signature="o", out_signature="u")
    def RequestPasskey(self, device):
        return dbus.UInt32(0)

    @dbus.service.method("org.bluez.Agent1", in_signature="ouq", out_signature="")
    def DisplayPasskey(self, device, passkey, entered):
        pass

    @dbus.service.method("org.bluez.Agent1", in_signature="os", out_signature="")
    def DisplayPinCode(self, device, pincode):
        pass

    @dbus.service.method("org.bluez.Agent1", in_signature="ou", out_signature="")
    def RequestConfirmation(self, device, passkey):
        return

    @dbus.service.method("org.bluez.Agent1", in_signature="o", out_signature="")
    def RequestAuthorization(self, device):
        return

    @dbus.service.method("org.bluez.Agent1", in_signature="", out_signature="")
    def Cancel(self):
        pass

def is_gamepad(props):
    name = str(props.get("Name", "")).lower()
    alias = str(props.get("Alias", "")).lower()
    icon = str(props.get("Icon", "")).lower()
    modalias = str(props.get("Modalias", "")).lower()

    if "input-gaming" in icon:
        return True
    gamepad_keywords = ["wireless controller", "controller", "gamepad", "dualshock", "dualsense", "xbox", "pro controller", "sony"]
    if any(k in name for k in gamepad_keywords) or any(k in alias for k in gamepad_keywords):
        return True
    # Sony DualShock 4 USB vendor/product
    if "v054cp09cc" in modalias or "v054cp05c4" in modalias:
        return True
    return False

def main():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()

    # Obtener el adaptador Bluetooth (hci0)
    manager = dbus.Interface(bus.get_object("org.bluez", "/"), "org.freedesktop.DBus.ObjectManager")
    objects = manager.GetManagedObjects()

    adapter_path = None
    for path, interfaces in objects.items():
        if "org.bluez.Adapter1" in interfaces:
            adapter_path = path
            break

    if not adapter_path:
        print("\033[1;31m[ERROR] No se encontró adaptador Bluetooth activo.\033[0m")
        sys.exit(1)

    adapter = dbus.Interface(bus.get_object("org.bluez", adapter_path), "org.bluez.Adapter1")
    adapter_props = dbus.Interface(bus.get_object("org.bluez", adapter_path), "org.freedesktop.DBus.Properties")

    # Asegurar que esté encendido
    adapter_props.Set("org.bluez.Adapter1", "Powered", dbus.Boolean(True))

    # Registrar agente
    agent = AutoAgent(bus, AGENT_PATH)
    agent_manager = dbus.Interface(bus.get_object("org.bluez", "/org/bluez"), "org.bluez.AgentManager1")
    try:
        agent_manager.RegisterAgent(AGENT_PATH, "NoInputNoOutput")
        agent_manager.RequestDefaultAgent(AGENT_PATH)
    except Exception:
        pass

    print("\033[1;36m====================================================\033[0m")
    print("\033[1;36m     VINCULACIÓN AUTOMÁTICA DE CONTROL BLUETOOTH    \033[0m")
    print("\033[1;36m====================================================\033[0m")
    print("\033[1;33mPor favor pon tu mando en MODO EMPAREJAMIENTO ahora:\033[0m")
    print("  • \033[1;32mDualShock 4 / PS4:\033[0m Mantén presionado \033[1mSHARE + botón PS\033[0m hasta que")
    print("    la barra de luz parpadee rápidamente (doble destello blanco continuo).")
    print("  • \033[1;32mXbox:\033[0m Mantén presionado el botón superior de sincronización ()))")
    print("    hasta que el logo de Xbox parpadee rápido.\n")
    print("\033[1;34m[>] Escaneando dispositivos cercanos (esperando al mando)...\033[0m")

    loop = GLib.MainLoop()
    paired_success = [False]

    def try_pair_device(dev_path, props):
        if not is_gamepad(props):
            return
        
        name = props.get("Name", props.get("Alias", "Mando Desconocido"))
        mac = props.get("Address", "??:??:??:??:??:??")
        print(f"\n\033[1;32m[+] ¡Mando detectado! -> {name} ({mac})\033[0m")
        print("    Iniciando vinculación y negociación limpia...")

        dev_obj = bus.get_object("org.bluez", dev_path)
        dev = dbus.Interface(dev_obj, "org.bluez.Device1")
        dev_props = dbus.Interface(dev_obj, "org.freedesktop.DBus.Properties")

        try:
            # Emparejar
            if not props.get("Paired", False):
                dev.Pair()
                print("    ✓ Emparejamiento completado con éxito.")
            # Confiar
            dev_props.Set("org.bluez.Device1", "Trusted", dbus.Boolean(True))
            print("    ✓ Dispositivo marcado como de confianza (Trusted).")
            # Conectar
            dev.Connect()
            print("    ✓ Conexión establecida.")
            paired_success[0] = True
            
            # Detener escaneo
            try:
                adapter.StopDiscovery()
            except Exception:
                pass
            
            # Esperar a que udev/kernel cree /dev/input/js*
            time.sleep(2)
            check_system_input()
            loop.quit()

        except Exception as e:
            print(f"\033[1;31m    [!] Error al vincular: {e}\033[0m")
            # Reintentar si es posible
            pass

    def check_system_input():
        js_list = glob.glob("/dev/input/js*")
        print("\n\033[1;36m====================================================\033[0m")
        if js_list:
            print("\033[1;32m¡MANDO RECONOCIDO CON ÉXITO EN EL SISTEMA!\033[0m")
            for js in js_list:
                js_num = os.path.basename(js)
                name_file = f"/sys/class/input/{js_num}/device/name"
                dev_name = "Dispositivo"
                if os.path.exists(name_file):
                    with open(name_file, "r") as f:
                        dev_name = f.read().strip()
                print(f"  • Nodo: \033[1;32m{js}\033[0m ({dev_name})")
            print("\n\033[1;33mEl mando ya está disponible en Steam, emuladores y navegadores para jugar.\033[0m")
        else:
            print("\033[1;33mEl dispositivo se conectó. Esperando inicialización del driver...\033[0m")
        print("\033[1;36m====================================================\033[0m")

    # Verificar si ya está en la lista de objetos descubiertos
    for path, interfaces in manager.GetManagedObjects().items():
        if "org.bluez.Device1" in interfaces:
            props = interfaces["org.bluez.Device1"]
            if is_gamepad(props):
                try_pair_device(path, props)
                if paired_success[0]:
                    return

    def interfaces_added(path, interfaces):
        if "org.bluez.Device1" in interfaces:
            props = interfaces["org.bluez.Device1"]
            try_pair_device(path, props)

    bus.add_signal_receiver(interfaces_added,
                            dbus_interface="org.freedesktop.DBus.ObjectManager",
                            signal_name="InterfacesAdded")

    def properties_changed(interface, changed, invalidated, path):
        if interface == "org.bluez.Device1" and not paired_success[0]:
            try:
                dev_obj = bus.get_object("org.bluez", path)
                props = dbus.Interface(dev_obj, "org.freedesktop.DBus.Properties").GetAll("org.bluez.Device1")
                try_pair_device(path, props)
            except Exception:
                pass

    bus.add_signal_receiver(properties_changed,
                            dbus_interface="org.freedesktop.DBus.Properties",
                            signal_name="PropertiesChanged",
                            path_keyword="path")

    # Iniciar descubrimiento
    try:
        adapter.StartDiscovery()
    except Exception as e:
        print(f"Error al iniciar escaneo: {e}")

    # Timeout de 300 segundos (5 minutos)
    def timeout():
        if not paired_success[0]:
            print("\n\033[1;33m[!] Tiempo de espera agotado (5 min). Ejecuta de nuevo cuando tengas el mando en mano.\033[0m")
            try:
                adapter.StopDiscovery()
            except Exception:
                pass
            loop.quit()
        return False

    GLib.timeout_add_seconds(300, timeout)

    try:
        loop.run()
    except KeyboardInterrupt:
        print("\nCancelado por el usuario.")
    finally:
        try:
            adapter.StopDiscovery()
        except Exception:
            pass

if __name__ == "__main__":
    main()
