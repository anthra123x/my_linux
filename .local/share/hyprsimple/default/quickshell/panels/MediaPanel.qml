import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import qs.theme
import qs.components

// Mini reproductor multimedia con diseno refinado, ambiente translúcido, ecualizador visual y controles táctiles.
PopupPanel {
    id: root

    panelWidth: 380

    readonly property var players: Mpris.players.values
    property int selectedIndex: -1
    property real lastVolume: 0.5

    // Formatea segundos a m:ss
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
    readonly property bool hasArt: artUrl !== ""
    readonly property string title: activePlayer?.trackTitle || "Sin reproduccion"
    readonly property string artist: activePlayer?.trackArtist || "Ninguna pista activa"
    readonly property string album: activePlayer?.trackAlbum || ""
    readonly property real progressFraction: {
        if (!activePlayer || !activePlayer.length || activePlayer.length <= 0) return 0
        return Math.min(1.0, Math.max(0.0, activePlayer.position / activePlayer.length))
    }

    // Cabecera superior: Chip de estado del reproductor y pestañas si hay múltiples fuentes
    RowLayout {
        width: parent.width

        // Chip de la fuente actual
        Rectangle {
            height: 24
            implicitWidth: headerRow.implicitWidth + 14
            radius: 12
            color: Qt.alpha(Theme.barFg, 0.08)
            border.width: 1
            border.color: Qt.alpha(Theme.barFg, 0.12)

            Row {
                id: headerRow
                anchors.centerIn: parent
                spacing: 6

                // Indicador de pulso
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 6
                    height: 6
                    radius: 3
                    color: root.isPlaying ? Theme.accent : Theme.barMuted

                    // Suave pulso cuando está en reproducción
                    SequentialAnimation on opacity {
                        running: root.isPlaying
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.35; duration: 900; easing.type: Easing.InOutQuad }
                        NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutQuad }
                    }
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.activePlayer ? root.activePlayer.identity : "Sin fuente"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: Theme.barFg
                }
            }
        }

        Item { Layout.fillWidth: true }

        // Pestañas compactas si hay más de un reproductor
        Row {
            visible: root.players.length > 1
            spacing: 4

            Repeater {
                model: root.players

                Rectangle {
                    required property var modelData
                    required property int index
                    readonly property bool isSelected: root.selectedIndex === index || (root.selectedIndex === -1 && root.activePlayer === modelData)

                    width: tabLabel.implicitWidth + 12
                    height: 22
                    radius: 11
                    color: isSelected ? Qt.alpha(Theme.accent, 0.22) : Qt.alpha(Theme.barFg, 0.06)
                    border.width: 1
                    border.color: isSelected ? Qt.alpha(Theme.accent, 0.50) : Qt.alpha(Theme.barFg, 0.10)

                    StyledText {
                        id: tabLabel
                        anchors.centerIn: parent
                        text: parent.modelData.identity
                        font.pixelSize: 10
                        font.weight: parent.isSelected ? Font.DemiBold : Font.Normal
                        color: parent.isSelected ? Theme.accent : Theme.barMuted
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

    // Escenario Principal: Tarjeta translúcida con fondo ambiental y carátula destacada
    Rectangle {
        width: parent.width
        implicitHeight: 108
        radius: 16
        color: Qt.alpha(Theme.barSurface, 0.55)
        border.width: 1
        border.color: Qt.alpha(Theme.barFg, 0.14)
        clip: true

        // Capa 1: Fondo ambiental difuminado de la carátula para dar calidez y vida
        Image {
            anchors.fill: parent
            source: root.artUrl
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            opacity: 0.20
            visible: root.hasArt && status === Image.Ready
        }

        // Capa 2: Degradado oscuro sutil para mantener contraste de texto
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.alpha(Theme.barBg, 0.40) }
                GradientStop { position: 1.0; color: Qt.alpha(Theme.barBg, 0.85) }
            }
        }

        // Capa 3: Contenido en primer plano (Carátula a la izquierda + Textos a la derecha)
        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 14

            // Contenedor de Carátula con bordes suaves y badge de ecualizador
            Rectangle {
                Layout.preferredWidth: 84
                Layout.preferredHeight: 84
                radius: 12
                color: Qt.alpha("#050508", 0.90)
                border.width: 1
                border.color: Qt.alpha(Theme.barFg, 0.18)
                clip: true

                // Imagen de la carátula
                Image {
                    id: coverImage
                    anchors.fill: parent
                    source: root.artUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    visible: status === Image.Ready && root.hasArt
                }

                // Placeholder gráfico tipo Vinilo cuando no hay carátula
                Item {
                    anchors.fill: parent
                    visible: !coverImage.visible

                    // Anillo exterior de vinilo
                    Rectangle {
                        anchors.centerIn: parent
                        width: 70
                        height: 70
                        radius: 35
                        color: "#121318"
                        border.width: 1
                        border.color: Qt.alpha(Theme.barFg, 0.20)

                        // Surcos concéntricos
                        Rectangle {
                            anchors.centerIn: parent
                            width: 50
                            height: 50
                            radius: 25
                            color: "transparent"
                            border.width: 1
                            border.color: Qt.alpha(Theme.barFg, 0.10)
                        }

                        // Centro del vinilo
                        Rectangle {
                            anchors.centerIn: parent
                            width: 26
                            height: 26
                            radius: 13
                            color: Qt.alpha(Theme.accent, 0.25)
                            border.width: 1
                            border.color: Theme.accent

                            Icon {
                                anchors.centerIn: parent
                                text: "music_note"
                                font.pixelSize: 14
                                color: Theme.accent
                            }
                        }
                    }
                }

                // Badge de mini-ecualizador animado en la esquina inferior derecha
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    anchors.margins: 5
                    width: 24
                    height: 18
                    radius: 4
                    color: Qt.alpha("#0c0d12", 0.82)
                    border.width: 1
                    border.color: Qt.alpha(Theme.barFg, 0.15)
                    visible: root.isPlaying

                    Row {
                        anchors.centerIn: parent
                        spacing: 2
                        bottomPadding: 1

                        // Barra 1
                        Rectangle {
                            width: 3
                            height: 6
                            radius: 1.5
                            color: Theme.accent
                            anchors.bottom: parent.bottom
                            SequentialAnimation on height {
                                running: root.isPlaying
                                loops: Animation.Infinite
                                NumberAnimation { to: 12; duration: 340; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 4; duration: 380; easing.type: Easing.InOutSine }
                            }
                        }

                        // Barra 2
                        Rectangle {
                            width: 3
                            height: 10
                            radius: 1.5
                            color: Theme.accent
                            anchors.bottom: parent.bottom
                            SequentialAnimation on height {
                                running: root.isPlaying
                                loops: Animation.Infinite
                                NumberAnimation { to: 4; duration: 420; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 14; duration: 360; easing.type: Easing.InOutSine }
                            }
                        }

                        // Barra 3
                        Rectangle {
                            width: 3
                            height: 8
                            radius: 1.5
                            color: Theme.accent
                            anchors.bottom: parent.bottom
                            SequentialAnimation on height {
                                running: root.isPlaying
                                loops: Animation.Infinite
                                NumberAnimation { to: 13; duration: 290; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 5; duration: 450; easing.type: Easing.InOutSine }
                            }
                        }
                    }
                }

                // Efecto hover sutil en la carátula
                MouseArea {
                    id: artMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.activePlayer?.togglePlaying()
                }

                scale: artMouse.containsMouse ? 1.03 : 1.0
                Behavior on scale { Anim { duration: 160 } }
            }

            // Columna de Metadatos
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 3

                // Título de la pista
                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    font.bold: true
                    font.pixelSize: 14
                    color: Theme.barFg
                    elide: Text.ElideRight
                }

                // Artista
                StyledText {
                    Layout.fillWidth: true
                    text: root.artist
                    font.weight: Font.Medium
                    font.pixelSize: 12
                    color: Qt.alpha(Theme.barFg, 0.72)
                    elide: Text.ElideRight
                }

                // Álbum si está disponible
                StyledText {
                    Layout.fillWidth: true
                    visible: root.album !== ""
                    text: root.album
                    font.pixelSize: 10
                    color: Theme.barMuted
                    elide: Text.ElideRight
                }

                // Estado en texto sutil
                StyledText {
                    Layout.topMargin: 2
                    text: root.activePlayer ? (root.isPlaying ? "En reproducción" : "Pausado") : "Desconectado"
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    color: root.isPlaying ? Theme.accent : Theme.barMuted
                }
            }
        }
    }

    // Línea de tiempo interactiva (Scrubber)
    Column {
        width: parent.width
        spacing: 4
        visible: root.activePlayer !== null && (root.activePlayer.length > 0)

        // Contenedor interactivo del scrubber
        Item {
            id: scrubber
            width: parent.width
            height: 18

            // Pista de fondo
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: scrubMouse.containsMouse || scrubMouse.pressed ? 6 : 4
                radius: height / 2
                color: Qt.alpha(Theme.barFg, 0.14)
                Behavior on height { Anim { duration: 140 } }

                // Pista completada con degradado
                Rectangle {
                    height: parent.height
                    radius: parent.radius
                    width: parent.width * root.progressFraction
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Theme.accent }
                        GradientStop { position: 1.0; color: Qt.lighter(Theme.accent, 1.25) }
                    }
                    Behavior on width { Anim { duration: scrubMouse.pressed ? 0 : 250 } }
                }
            }

            // Cabezal de arrastre (Thumb) visible en hover o reproducción
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: Math.max(0, Math.min(scrubber.width - width, (scrubber.width * root.progressFraction) - (width / 2)))
                width: scrubMouse.containsMouse || scrubMouse.pressed ? 12 : 8
                height: width
                radius: width / 2
                color: Theme.barFg
                border.width: 2
                border.color: Theme.accent
                scale: scrubMouse.pressed ? 1.25 : (scrubMouse.containsMouse ? 1.1 : 0.8)
                Behavior on scale { Anim { duration: 120 } }
                Behavior on width { Anim { duration: 120 } }
            }

            // Detección de clics y arrastre para salto de posición (Seeking)
            MouseArea {
                id: scrubMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                function seekTo(mouseXVal) {
                    if (!root.activePlayer || !root.activePlayer.length || root.activePlayer.length <= 0) return
                    const fraction = Math.max(0.0, Math.min(1.0, mouseXVal / width))
                    root.activePlayer.position = fraction * root.activePlayer.length
                }

                onClicked: mouse => seekTo(mouse.x)
                onPositionChanged: mouse => {
                    if (pressed) seekTo(mouse.x)
                }
            }
        }

        // Tiempos numéricos (Transcurrido y Restante)
        RowLayout {
            width: parent.width

            StyledText {
                text: root.formatTime(root.activePlayer?.position)
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 10
                font.weight: Font.Medium
                color: Theme.barFg
                opacity: 0.85
            }

            Item { Layout.fillWidth: true }

            StyledText {
                text: "-" + root.formatTime((root.activePlayer?.length ?? 0) - (root.activePlayer?.position ?? 0))
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 10
                font.weight: Font.Medium
                color: Theme.barMuted
            }
        }
    }

    // Controles de Reproducción: Esculpido moderno y botones con micro-interacciones táctiles
    Item {
        width: parent.width
        implicitHeight: 56

        Row {
            anchors.centerIn: parent
            spacing: 20

            // Botón Anterior
            Rectangle {
                width: 38
                height: 38
                radius: 19
                anchors.verticalCenter: parent.verticalCenter
                color: prevHover.pressed ? Qt.alpha(Theme.barFg, 0.20) : (prevHover.containsMouse ? Qt.alpha(Theme.barFg, 0.10) : "transparent")
                border.width: 1
                border.color: prevHover.containsMouse ? Qt.alpha(Theme.barFg, 0.18) : "transparent"
                opacity: root.activePlayer?.canGoPrevious ? 1.0 : 0.35
                scale: prevHover.pressed ? 0.90 : (prevHover.containsMouse ? 1.06 : 1.0)
                Behavior on scale { Anim { duration: 120 } }
                Behavior on color { CAnim { duration: 120 } }

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

            // Botón Principal Play / Pausa (Héroe central con gradiente de acento)
            Rectangle {
                width: 50
                height: 50
                radius: 25
                anchors.verticalCenter: parent.verticalCenter
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: playHover.containsMouse ? Qt.lighter(Theme.accent, 1.15) : Theme.accent }
                    GradientStop { position: 1.0; color: Theme.accent }
                }
                border.width: 2
                border.color: Qt.alpha(Theme.accent, 0.35)
                opacity: root.activePlayer ? 1.0 : 0.5
                scale: playHover.pressed ? 0.91 : (playHover.containsMouse ? 1.07 : 1.0)
                Behavior on scale { Anim { duration: 140 } }

                Icon {
                    anchors.centerIn: parent
                    text: root.isPlaying ? "pause" : "play_arrow"
                    font.pixelSize: 28
                    color: Theme.onAccent
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

            // Botón Siguiente
            Rectangle {
                width: 38
                height: 38
                radius: 19
                anchors.verticalCenter: parent.verticalCenter
                color: nextHover.pressed ? Qt.alpha(Theme.barFg, 0.20) : (nextHover.containsMouse ? Qt.alpha(Theme.barFg, 0.10) : "transparent")
                border.width: 1
                border.color: nextHover.containsMouse ? Qt.alpha(Theme.barFg, 0.18) : "transparent"
                opacity: root.activePlayer?.canGoNext ? 1.0 : 0.35
                scale: nextHover.pressed ? 0.90 : (nextHover.containsMouse ? 1.06 : 1.0)
                Behavior on scale { Anim { duration: 120 } }
                Behavior on color { CAnim { duration: 120 } }

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

    // Separador sutil
    Rectangle {
        width: parent.width
        height: 1
        color: Qt.alpha(Theme.barFg, 0.08)
        visible: root.activePlayer?.volumeSupported ?? false
    }

    // Control de volumen integrado con conmutador de silencio
    RowLayout {
        width: parent.width
        visible: root.activePlayer?.volumeSupported ?? false
        spacing: 8

        // Botón de mute rápido al hacer clic en el icono de volumen
        Rectangle {
            width: 28
            height: 28
            radius: 14
            color: volMuteHover.containsMouse ? Qt.alpha(Theme.barFg, 0.10) : "transparent"

            Icon {
                anchors.centerIn: parent
                text: {
                    const vol = root.activePlayer?.volume ?? 0
                    if (vol <= 0.001) return "volume_off"
                    if (vol < 0.5) return "volume_down"
                    return "volume_up"
                }
                font.pixelSize: 16
                color: (root.activePlayer?.volume ?? 0) <= 0.001 ? Theme.danger : Theme.barFg
            }

            MouseArea {
                id: volMuteHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (!root.activePlayer) return
                    if (root.activePlayer.volume > 0.001) {
                        root.lastVolume = root.activePlayer.volume
                        root.activePlayer.volume = 0
                    } else {
                        root.activePlayer.volume = root.lastVolume > 0.001 ? root.lastVolume : 0.5
                    }
                }
            }
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
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 11
            font.weight: Font.DemiBold
            color: Theme.barFg
            text: `${Math.round((root.activePlayer?.volume ?? 0) * 100)}%`
        }
    }
}
