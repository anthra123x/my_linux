import QtQuick
import Quickshell.Hyprland
import qs.theme

// Boton de la barra para inspeccionar aplicaciones activas y en segundo plano.
StatusButton {
    id: root

    readonly property var toplevels: Hyprland.toplevels.values
    readonly property int totalCount: toplevels ? toplevels.length : 0
    readonly property int bgCount: {
        if (!toplevels) return 0
        let count = 0
        for (let i = 0; i < toplevels.length; i++) {
            if (!toplevels[i].activated) count++
        }
        return count
    }

    icon: "layers"
    label: totalCount > 0 ? String(totalCount) : ""
    dim: totalCount === 0
    highlighted: bgCount > 0
    tooltip: totalCount > 0
        ? `${totalCount} aplicaciones abiertas (${bgCount} en segundo plano)`
        : "Sin aplicaciones en ejecucion"
}
