import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.theme
import qs.components

// Panel para inspeccionar, conmutar y finalizar aplicaciones activas y en segundo plano.
PopupPanel {
    id: root

    panelWidth: 420

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
    property bool confirmingCloseAll: false

    Timer {
        id: resetConfirmTimer
        interval: 3500
        onTriggered: root.confirmingCloseAll = false
    }

    function getAppClass(tl) {
        if (!tl) return ""
        if (tl.wayland && tl.wayland.appId && tl.wayland.appId.length > 0) {
            return tl.wayland.appId.toLowerCase()
        }
        if (tl.lastIpcObject) {
            if (tl.lastIpcObject.class && tl.lastIpcObject.class.length > 0) {
                return tl.lastIpcObject.class.toLowerCase()
            }
            if (tl.lastIpcObject.initialClass && tl.lastIpcObject.initialClass.length > 0) {
                return tl.lastIpcObject.initialClass.toLowerCase()
            }
        }
        const title = (tl.title || (tl.lastIpcObject && tl.lastIpcObject.title) || "").toLowerCase()
        if (title.includes("discord")) return "discord"
        if (title.includes("spotify")) return "spotify"
        if (title.includes("brave")) return "brave-browser"
        if (title.includes("firefox")) return "firefox"
        if (title.includes("chrome")) return "google-chrome"
        if (title.includes("antigravity")) return "antigravity-ide"
        if (title.includes("steam")) return "steam"
        if (title.includes("kitty")) return "kitty"
        if (title.includes("ghostty")) return "ghostty"
        if (title.includes("alacritty")) return "alacritty"
        if (title.includes("code")) return "code"
        if (title.includes("pseint")) return "pseint"
        return ""
    }

    function getAppIcon(tl) {
        const cls = getAppClass(tl)
        if (!cls) return ""

        let icon = Quickshell.iconPath(cls, true)
        if (icon) return icon

        if (cls.includes("brave")) {
            icon = Quickshell.iconPath("brave-browser", true) || Quickshell.iconPath("brave-desktop", true)
            if (icon) return icon
        }
        if (cls.includes("antigravity")) {
            icon = Quickshell.iconPath("antigravity-ide", true) || Quickshell.iconPath("antigravity", true)
            if (icon) return icon
        }
        if (cls.includes("discord")) {
            icon = Quickshell.iconPath("discord", true)
            if (icon) return icon
        }
        if (cls.includes("spotify")) {
            icon = Quickshell.iconPath("spotify", true)
            if (icon) return icon
        }
        if (cls.includes("code")) {
            icon = Quickshell.iconPath("code", true) || Quickshell.iconPath("visual-studio-code", true)
            if (icon) return icon
        }
        if (cls.includes("terminal") || cls.includes("kitty") || cls.includes("ghostty")) {
            icon = Quickshell.iconPath("utilities-terminal", true) || Quickshell.iconPath("terminal", true)
            if (icon) return icon
        }

        return ""
    }

    function closeWindow(tl) {
        if (!tl) return
        const rawAddr = tl.address || (tl.lastIpcObject && tl.lastIpcObject.address) || ""
        const addr = rawAddr.startsWith("0x") ? rawAddr : ("0x" + rawAddr)
        Hyprland.dispatch("hl.dsp.window.close({ address = '" + addr + "' })")
        Hyprland.dispatch("closewindow address:" + addr)
        if (tl.wayland && typeof tl.wayland.close === "function") {
            tl.wayland.close()
        }
    }

    function focusWindow(tl) {
        if (!tl) return
        const rawAddr = tl.address || (tl.lastIpcObject && tl.lastIpcObject.address) || ""
        const addr = rawAddr.startsWith("0x") ? rawAddr : ("0x" + rawAddr)
        Hyprland.dispatch("hl.dsp.focus({ window = 'address:" + addr + "' })")
        Hyprland.dispatch("focuswindow address:" + addr)
        if (tl.wayland && typeof tl.wayland.activate === "function") {
            tl.wayland.activate()
        }
    }

    // Cierra todas las ventanas que no esten activas en foco
    function closeInactive() {
        if (!confirmingCloseAll) {
            confirmingCloseAll = true
            resetConfirmTimer.restart()
            return
        }

        confirmingCloseAll = false
        resetConfirmTimer.stop()

        if (!toplevels) return
        for (let i = 0; i < toplevels.length; i++) {
            const tl = toplevels[i]
            if (!tl.activated && (tl.address || (tl.lastIpcObject && tl.lastIpcObject.address))) {
                root.closeWindow(tl)
            }
        }
    }

    // Cabecera del panel
    RowLayout {
        width: parent.width

        Row {
            Layout.fillWidth: true
            spacing: Theme.xs

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                text: "layers"
                font.pixelSize: 16
                color: Theme.accent
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: "Segundo Plano & Tareas"
                font.bold: true
                color: Theme.barFg
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: `(${root.totalCount})`
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.barMuted
            }
        }

        // Accion para cerrar ventanas inactivas con confirmacion
        Rectangle {
            visible: root.totalCount > 1
            width: closeAllText.implicitWidth + Theme.md
            height: 22
            radius: 11
            color: root.confirmingCloseAll
                ? Theme.danger
                : (closeAllHover.containsMouse ? Qt.alpha(Theme.danger, 0.25) : Qt.alpha(Theme.barSurface, 0.70))
            border.width: 1
            border.color: root.confirmingCloseAll ? Theme.danger : (closeAllHover.containsMouse ? Theme.danger : Qt.alpha(Theme.barFg, 0.15))
            Behavior on color { CAnim {} }

            StyledText {
                id: closeAllText
                anchors.centerIn: parent
                text: root.confirmingCloseAll ? "Confirmar cierre" : "Cerrar inactivas"
                font.pixelSize: 10
                font.weight: Font.DemiBold
                color: root.confirmingCloseAll ? Theme.barBg : (closeAllHover.containsMouse ? Theme.danger : Theme.barFg)
            }

            MouseArea {
                id: closeAllHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.closeInactive()
            }
        }
    }

    // Indicacion de uso
    StyledText {
        width: parent.width
        text: "Toca una aplicacion para enfocarla o pulsa en la cruz para cerrarla."
        font.pixelSize: 10
        color: Theme.barMuted
    }

    // Lista scrolleable de ventanas
    Flickable {
        width: parent.width
        height: Math.min(appListColumn.implicitHeight, 340)
        contentHeight: appListColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        visible: root.totalCount > 0

        Column {
            id: appListColumn
            width: parent.width
            spacing: Theme.xs

            Repeater {
                model: root.toplevels

                Rectangle {
                    id: rowCard
                    required property var modelData

                    readonly property string appClass: root.getAppClass(modelData)
                    readonly property string appIconSrc: root.getAppIcon(modelData)

                    width: parent.width
                    height: 48
                    radius: 8
                    color: rowHover.containsMouse ? Qt.alpha(Theme.barSurface, 0.90) : Qt.alpha(Theme.barSurface, 0.65)
                    border.width: 1
                    border.color: modelData.activated ? Theme.accent : (rowHover.containsMouse ? Qt.alpha(Theme.barFg, 0.25) : Qt.alpha(Theme.barFg, 0.08))
                    Behavior on color { CAnim {} }
                    Behavior on border.color { CAnim {} }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.sm
                        anchors.rightMargin: Theme.sm
                        spacing: Theme.sm

                        // Icono de la aplicacion
                        Rectangle {
                            Layout.preferredWidth: 30
                            Layout.preferredHeight: 30
                            radius: 6
                            color: Qt.alpha(Theme.barBg, 0.70)
                            border.width: 1
                            border.color: Qt.alpha(Theme.barFg, 0.12)
                            clip: true

                            Image {
                                id: appImg
                                anchors.centerIn: parent
                                width: 22
                                height: 22
                                sourceSize: Qt.size(44, 44)
                                source: rowCard.appIconSrc
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                visible: status === Image.Ready && rowCard.appIconSrc !== ""
                            }

                            Icon {
                                anchors.centerIn: parent
                                visible: !appImg.visible || rowCard.appIconSrc === ""
                                text: "apps"
                                font.pixelSize: 16
                                color: Theme.barMuted
                            }
                        }

                        // Metadatos de la ventana
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 2

                            StyledText {
                                Layout.fillWidth: true
                                text: rowCard.modelData.title || rowCard.modelData.lastIpcObject?.title || rowCard.modelData.lastIpcObject?.initialTitle || "Ventana"
                                font.weight: rowCard.modelData.activated ? Font.Bold : Font.Normal
                                font.pixelSize: Theme.fontSize
                                color: rowCard.modelData.activated ? Theme.accent : Theme.barFg
                                elide: Text.ElideRight
                            }

                            Row {
                                spacing: Theme.xs

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: wsLabel.implicitWidth + 8
                                    height: 14
                                    radius: 7
                                    color: Qt.alpha(Theme.barAccent, 0.25)

                                    StyledText {
                                        id: wsLabel
                                        anchors.centerIn: parent
                                        text: `WS ${rowCard.modelData.workspace ? rowCard.modelData.workspace.id : (rowCard.modelData.lastIpcObject?.workspace?.id ?? "?")}`
                                        font.pixelSize: 9
                                        color: Theme.barFg
                                    }
                                }

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: rowCard.appClass || "app"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.barMuted
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: rowCard.modelData.activated
                                    text: "· En foco"
                                    font.pixelSize: 10
                                    color: Theme.accent
                                }
                            }
                        }

                        // Boton de cierre de la ventana
                        Rectangle {
                            Layout.preferredWidth: 26
                            Layout.preferredHeight: 26
                            radius: 13
                            color: btnCloseHover.containsMouse ? Qt.alpha(Theme.danger, 0.30) : Qt.alpha(Theme.barFg, 0.08)
                            border.width: 1
                            border.color: btnCloseHover.containsMouse ? Theme.danger : "transparent"
                            Behavior on color { CAnim {} }

                            Icon {
                                anchors.centerIn: parent
                                text: "close"
                                font.pixelSize: 15
                                color: btnCloseHover.containsMouse ? Theme.danger : Theme.barFg
                                Behavior on color { CAnim {} }
                            }

                            MouseArea {
                                id: btnCloseHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.closeWindow(rowCard.modelData)
                            }
                        }
                    }

                    // Click en el cuerpo de la fila para enfocar la aplicacion
                    MouseArea {
                        id: rowHover
                        anchors.fill: parent
                        anchors.rightMargin: 36 // Permite al boton de cerrar recibir clicks
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.focusWindow(rowCard.modelData)
                            root.dismiss()
                        }
                    }
                }
            }
        }
    }

    // Estado vacio cuando no hay aplicaciones abiertas
    Item {
        width: parent.width
        implicitHeight: 80
        visible: root.totalCount === 0

        Column {
            anchors.centerIn: parent
            spacing: Theme.xs

            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "check_circle"
                font.pixelSize: 28
                color: Theme.barMuted
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "No hay aplicaciones en ejecucion"
                color: Theme.barMuted
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }
}
