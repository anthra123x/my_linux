import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import qs.theme
import qs.components

// Mini reproductor multimedia con diseno moderno, minimalista y efecto de desenfoque.
PopupPanel {
    id: root

    panelWidth: 380

    readonly property var players: Mpris.players.values
    property int selectedIndex: 0

    // Formatea segundos a mm:ss
    function formatTime(totalSeconds) {
        if (!totalSeconds || isNaN(totalSeconds) || totalSeconds < 0) return "0:00"
        const m = Math.floor(totalSeconds / 60)
        const s = Math.floor(totalSeconds % 60)
        return `${m}:${s < 10 ? "0" : ""}${s}`
    }

    // Selecciona el reproductor activo o el elegido por el usuario
    readonly property var activePlayer: {
        if (!players || players.length === 0) return null
        if (selectedIndex >= 0 && selectedIndex < players.length) return players[selectedIndex]
        for (let i = 0; i < players.length; i++) {
            if (players[i].playbackState === MprisPlaybackState.Playing) return players[i]
        }
        return players[0]
    }

    readonly property bool isPlaying: activePlayer?.playbackState === MprisPlaybackState.Playing
    readonly property string artUrl: activePlayer?.trackArtUrl || ""
    readonly property string title: activePlayer?.trackTitle || "Sin reproduccion"
    readonly property string artist: activePlayer?.trackArtist || "Ninguna pista activa"
    readonly property real progressFraction: {
        if (!activePlayer || !activePlayer.length || activePlayer.length <= 0) return 0
        return Math.min(1.0, Math.max(0.0, activePlayer.position / activePlayer.length))
    }

    // Cabecera: Nombre de la aplicacion / selector si hay multiples fuentes
    RowLayout {
        width: parent.width

        Row {
            Layout.fillWidth: true
            spacing: Theme.xs

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                text: "graphic_eq"
                font.pixelSize: 14
                color: root.isPlaying ? Theme.accent : Theme.barMuted
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.activePlayer ? root.activePlayer.identity : "Multimedia"
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.DemiBold
                color: Theme.barFg
            }
        }

        // Pildoras de seleccion de reproductor si hay mas de uno
        Row {
            visible: root.players.length > 1
            spacing: Theme.xs

            Repeater {
                model: root.players

                Rectangle {
                    required property var modelData
                    required property int index

                    width: playerLabel.implicitWidth + Theme.md
                    height: 20
                    radius: 10
                    color: root.selectedIndex === index ? Qt.alpha(Theme.barAccent, 0.3) : Qt.alpha(Theme.barSurface, 0.6)
                    border.width: 1
                    border.color: root.selectedIndex === index ? Qt.alpha(Theme.barFg, 0.4) : Qt.alpha(Theme.barFg, 0.1)

                    StyledText {
                        id: playerLabel
                        anchors.centerIn: parent
                        text: parent.modelData.identity
                        font.pixelSize: 10
                        color: root.selectedIndex === parent.index ? Theme.barFg : Theme.barMuted
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectedIndex = parent.index
                    }
                }
            }
        }
    }

    // Tarjeta central: Caratula + Metadatos de la cancion
    Rectangle {
        width: parent.width
        implicitHeight: 96
        radius: 12
        color: Qt.alpha(Theme.barSurface, 0.65)
        border.width: 1
        border.color: Qt.alpha(Theme.barFg, 0.12)

        RowLayout {
            anchors.fill: parent
            anchors.margins: Theme.sm
            spacing: Theme.md

            // Contenedor de la caratula del album
            Rectangle {
                Layout.preferredWidth: 80
                Layout.preferredHeight: 80
                radius: 10
                color: Qt.alpha(Theme.barBg, 0.85)
                border.width: 1
                border.color: Qt.alpha(Theme.barFg, 0.18)
                clip: true

                Image {
                    id: coverImage
                    anchors.fill: parent
                    source: root.artUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    visible: status === Image.Ready && root.artUrl !== ""
                }

                Icon {
                    anchors.centerIn: parent
                    visible: !coverImage.visible
                    text: "album"
                    font.pixelSize: 38
                    color: Qt.alpha(Theme.barMuted, 0.6)
                }
            }

            // Metadatos: Titulo y artista
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 4

                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    font.bold: true
                    font.pixelSize: Theme.fontSize + 2
                    color: Theme.barFg
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.artist
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.barMuted
                    elide: Text.ElideRight
                }

                // Estado de reproduccion
                Row {
                    spacing: Theme.xs
                    visible: root.activePlayer !== null

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 6
                        height: 6
                        radius: 3
                        color: root.isPlaying ? Theme.accent : Theme.barMuted
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.isPlaying ? "Reproduciendo" : "En pausa"
                        font.pixelSize: 10
                        color: Theme.barMuted
                    }
                }
            }
        }
    }

    // Barra de progreso y duracion de la pista
    Column {
        width: parent.width
        spacing: 4
        visible: root.activePlayer !== null && (root.activePlayer.length > 0)

        Rectangle {
            width: parent.width
            height: 4
            radius: 2
            color: Qt.alpha(Theme.barFg, 0.15)

            Rectangle {
                height: parent.height
                radius: 2
                width: parent.width * root.progressFraction
                color: Theme.accent
                Behavior on width { Anim { duration: 250 } }
            }
        }

        RowLayout {
            width: parent.width

            StyledText {
                text: root.formatTime(root.activePlayer?.position)
                font.pixelSize: 10
                color: Theme.barFg
                opacity: 0.85
            }

            Item { Layout.fillWidth: true }

            StyledText {
                text: root.formatTime(root.activePlayer?.length)
                font.pixelSize: 10
                color: Theme.barFg
                opacity: 0.85
            }
        }
    }

    // Controles de reproduccion (Anterior, Reproducir/Pausa, Siguiente)
    Item {
        width: parent.width
        implicitHeight: 48

        Row {
            anchors.centerIn: parent
            spacing: Theme.lg

            // Boton Anterior
            Rectangle {
                width: 34
                height: 34
                radius: 17
                color: prevHover.containsMouse ? Qt.alpha(Theme.barFg, 0.15) : "transparent"
                opacity: root.activePlayer?.canGoPrevious ? 1.0 : 0.35
                Behavior on color { CAnim {} }

                Icon {
                    anchors.centerIn: parent
                    text: "skip_previous"
                    font.pixelSize: 22
                    color: Theme.barFg
                }

                MouseArea {
                    id: prevHover
                    anchors.fill: parent
                    enabled: root.activePlayer?.canGoPrevious ?? false
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    hoverEnabled: true
                    onClicked: root.activePlayer?.previous()
                }
            }

            // Boton Principal Play/Pausa
            Rectangle {
                width: 44
                height: 44
                radius: 22
                color: playHover.containsMouse ? Theme.fg : Theme.barFg
                opacity: root.activePlayer ? 1.0 : 0.5
                Behavior on color { CAnim {} }

                Icon {
                    anchors.centerIn: parent
                    text: root.isPlaying ? "pause" : "play_arrow"
                    font.pixelSize: 26
                    color: Theme.barBg
                }

                MouseArea {
                    id: playHover
                    anchors.fill: parent
                    enabled: root.activePlayer !== null
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    hoverEnabled: true
                    onClicked: root.activePlayer?.togglePlaying()
                }
            }

            // Boton Siguiente
            Rectangle {
                width: 34
                height: 34
                radius: 17
                color: nextHover.containsMouse ? Qt.alpha(Theme.barFg, 0.15) : "transparent"
                opacity: root.activePlayer?.canGoNext ? 1.0 : 0.35
                Behavior on color { CAnim {} }

                Icon {
                    anchors.centerIn: parent
                    text: "skip_next"
                    font.pixelSize: 22
                    color: Theme.barFg
                }

                MouseArea {
                    id: nextHover
                    anchors.fill: parent
                    enabled: root.activePlayer?.canGoNext ?? false
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    hoverEnabled: true
                    onClicked: root.activePlayer?.next()
                }
            }
        }
    }

    // Control de volumen individual del reproductor si es soportado
    RowLayout {
        width: parent.width
        visible: root.activePlayer?.volumeSupported ?? false
        spacing: Theme.sm

        Icon {
            text: "volume_up"
            font.pixelSize: 16
            color: Theme.barFg
        }

        Slider {
            Layout.fillWidth: true
            value: root.activePlayer?.volume ?? 0.5
            onMoved: val => {
                if (root.activePlayer) root.activePlayer.volume = val
            }
        }

        StyledText {
            Layout.preferredWidth: Theme.percentWidth
            horizontalAlignment: Text.AlignRight
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.barFg
            text: `${Math.round((root.activePlayer?.volume ?? 0) * 100)}%`
        }
    }
}
