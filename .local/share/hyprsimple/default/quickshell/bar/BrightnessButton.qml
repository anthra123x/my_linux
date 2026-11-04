import QtQuick
import Quickshell
import Quickshell.Io
import qs.theme
import qs.components

// Screen brightness button with scroll and click controls.
// Left-click: +10% | Right-click: -10% | Mouse wheel: +/- 5%
StatusButton {
    id: root

    property int brightnessRaw: 80000
    property int maxBrightnessRaw: 96000
    readonly property real level: maxBrightnessRaw > 0 ? (brightnessRaw / maxBrightnessRaw) : 0.8
    readonly property int percentage: Math.round(level * 100)

    property real wheelDelta: 0

    visible: true
    icon: percentage < 35 ? (Theme.icon.brightness ? Theme.icon.brightness[0] : "brightness_low")
        : percentage < 70 ? (Theme.icon.brightness ? Theme.icon.brightness[1] : "brightness_medium")
        : (Theme.icon.brightness ? Theme.icon.brightness[2] : "brightness_high")
    label: `${percentage}%`
    tooltip: `Brillo: ${percentage}% (Rueda o clic izq/der para subir/bajar)`

    function setBrightness(deltaPercent) {
        let newPercent = Math.max(5, Math.min(100, percentage + deltaPercent))
        brightnessRaw = Math.round((newPercent / 100) * maxBrightnessRaw)
        Quickshell.execDetached(["brightnessctl", "s", `${newPercent}%`])
    }

    FileView {
        id: brightnessFile
        path: "/sys/class/backlight/intel_backlight/brightness"
        printErrors: false
        onLoaded: {
            const val = parseInt(text().trim())
            if (!isNaN(val) && val >= 0) root.brightnessRaw = val
        }
    }

    FileView {
        id: maxBrightnessFile
        path: "/sys/class/backlight/intel_backlight/max_brightness"
        printErrors: false
        onLoaded: {
            const val = parseInt(text().trim())
            if (!isNaN(val) && val > 0) root.maxBrightnessRaw = val
        }
    }

    Timer {
        interval: 1500
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            brightnessFile.reload()
            if (root.maxBrightnessRaw <= 100) maxBrightnessFile.reload()
        }
    }

    // Click izquierdo: +10%
    onClicked: root.setBrightness(10)

    // Click derecho: -10%
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: root.setBrightness(-10)
    }

    // Rueda del ratón / touchpad scroll: +/- 5%
    WheelHandler {
        onWheel: event => {
            root.wheelDelta += event.angleDelta.y
            if (Math.abs(root.wheelDelta) < 120) return
            const step = root.wheelDelta > 0 ? 5 : -5
            root.setBrightness(step)
            root.wheelDelta = 0
        }
    }
}
