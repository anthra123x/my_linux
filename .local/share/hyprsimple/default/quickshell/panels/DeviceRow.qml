import QtQuick
import Quickshell.Bluetooth
import qs.theme
import qs.components

// One bluetooth device. The owning panel handles clicks.
ListRow {
    id: row

    required property var device
    readonly property bool known: device.paired || device.bonded
    readonly property bool busy: device.pairing
        || device.state === BluetoothDeviceState.Connecting
        || device.state === BluetoothDeviceState.Disconnecting

    icon: Theme.btIcon(device.icon)
    readonly property bool hasRealAlias: Boolean(device.name && device.name.trim() !== "" && !/^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$/.test(device.name.trim()))
    title: hasRealAlias ? device.name : ((device.deviceName && device.deviceName.trim() !== "") ? device.deviceName : (device.name ?? device.address ?? "Dispositivo"))
    active: device.connected
    subtitle: device.pairing ? "Pairing…"
        : device.state === BluetoothDeviceState.Connecting ? "Connecting…"
        : device.state === BluetoothDeviceState.Disconnecting ? "Disconnecting…"
        : device.connected && device.batteryAvailable ? `Battery ${Math.round(device.battery * 100)}%`
        : ""

    trailing: [
        IconButton {
            visible: row.hovered && row.known && !row.busy
            icon: Theme.icon.trash
            iconColor: Theme.danger
            onClicked: row.device.forget()
        },
        IconButton {
            icon: row.device.connected ? Theme.icon.unlink : Theme.icon.link
            filled: row.device.connected
            busy: row.busy
            onClicked: row.clicked()
        }
    ]
}
