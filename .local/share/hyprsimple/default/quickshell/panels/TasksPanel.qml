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

    readonly property var toplevels: Hyprland.toplevels.values
    readonly property int totalCount: toplevels ? toplevels.length : 0
    property bool confirmingCloseAll: false

    Timer {
        id: resetConfirmTimer
        interval: 3500
        onTriggered: root.confirmingCloseAll = false
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
            if (!tl.activated && tl.address) {
                const addr = tl.address.startsWith("0x") ? tl.address : ("0x" + tl.address)
                Hyprland.dispatch("closewindow address:" + addr)
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
                                anchors.centerIn: parent
                                width: 22
                                height: 22
                                sourceSize: Qt.size(44, 44)
                                source: Quickshell.iconPath(rowCard.modelData.lastIpcObject?.class || "", "application-x-executable")
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                            }
                        }

                        // Metadatos de la ventana
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 2

                            StyledText {
                                Layout.fillWidth: true
                                text: rowCard.modelData.title || rowCard.modelData.lastIpcObject?.initialTitle || "Ventana"
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
                                        text: `WS ${rowCard.modelData.workspace?.id ?? "?"}`
                                        font.pixelSize: 9
                                        color: Theme.barFg
                                    }
                                }

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: rowCard.modelData.lastIpcObject?.class || "app"
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
                                onClicked: {
                                    const addr = rowCard.modelData.address.startsWith("0x") ? rowCard.modelData.address : ("0x" + rowCard.modelData.address)
                                    Hyprland.dispatch("closewindow address:" + addr)
                                }
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
                            const addr = rowCard.modelData.address.startsWith("0x") ? rowCard.modelData.address : ("0x" + rowCard.modelData.address)
                            Hyprland.dispatch("focuswindow address:" + addr)
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
