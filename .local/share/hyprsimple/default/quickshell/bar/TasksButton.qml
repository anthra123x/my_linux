import QtQuick
import Quickshell.Hyprland
import qs.theme

// Boton de la barra para inspeccionar aplicaciones activas y en segundo plano.
StatusButton {
    id: root

    function isValidToplevel(tl) {
        if (!tl) return false
        if (tl.lastIpcObject) {
            if (tl.lastIpcObject.mapped === false) return false
            if (tl.lastIpcObject.hidden === true) return false
            const ipcClass = (tl.lastIpcObject.class || "").toLowerCase()
            const ipcInitialClass = (tl.lastIpcObject.initialClass || "").toLowerCase()
            const ipcTitle = (tl.lastIpcObject.title || "").trim()
            if (!ipcTitle || ipcTitle === "Default IME" || ipcTitle.startsWith("Default IME")) return false
            if (ipcTitle === "SteamVR Status" || ipcTitle.startsWith("SteamVR")) return false
            if (ipcClass === "wine" || ipcInitialClass === "wine") return false
        }

        const title = (tl.title || (tl.lastIpcObject && tl.lastIpcObject.title) || "").trim()
        if (!title) return false
        if (title === "Default IME" || title.startsWith("Default IME")) return false
        if (title === "SteamVR Status" || title.startsWith("SteamVR")) return false

        const wsId = tl.workspace ? tl.workspace.id : (tl.lastIpcObject && tl.lastIpcObject.workspace ? tl.lastIpcObject.workspace.id : null)
        if (wsId === undefined || wsId === null || wsId <= 0) return false

        return true
    }

    readonly property var toplevels: {
        const raw = Hyprland.toplevels.values
        if (!raw) return []
        return raw.filter(isValidToplevel)
    }
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
