import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Mpris
import qs.theme
import qs.components

// Isla dinamica expandida (Dynamic Island) con estetica Apple / iOS:
// - Morfismo suave: Se expande fluidamente hacia abajo desde la barra conservando la posicion de la isla compacta.
// - Reproductor de musica fiel a la referencia:
//   * Caratula circular en la esquina superior izquierda.
//   * Titulo y artista destacados en el encabezado.
//   * Badge de fuente / accion interactivo a la derecha.
//   * Barra de desplazamiento (scrubber) con tiempos transcurrido y restante.
//   * Controles de reproduccion: Shuffle, Anterior, Boton circular blanco solido Play/Pause, Siguiente, Repetir.
// - Atmosfera adaptativa: Resplandor ambiental y tonalidades sincronizadas con la fuente activa (Spotify verde, Brave naranja, etc.).
PanelWindow {
    id: root

    required property var bar
    property Item anchorItem: null
    readonly property bool open: bar.openPanel === "media"
    property real progress: 0.0

    // Animacion de apertura con curva Bezier elastica tipo iOS
    NumberAnimation {
        id: opening
        target: root
        property: "progress"
        to: 1.0
        duration: 320
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.16, 1, 0.3, 1, 1, 1]
    }

    // Animacion de cierre rapida y precisa
    NumberAnimation {
        id: closing
        target: root
        property: "progress"
        to: 0.0
        duration: 220
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.3, 0, 0.8, 0.15, 1, 1]
    }

    onOpenChanged: {
        if (open) {
            closing.stop()
            opening.start()
            Qt.callLater(() => card.forceActiveFocus())
        } else {
            opening.stop()
            closing.start()
        }
    }

    function dismiss() {
        if (open) bar.openPanel = ""
    }

    screen: bar.screen
    visible: open || closing.running
    anchors { top: true; bottom: true; left: true; right: true }
    margins.top: -Theme.barHeight
    color: "transparent"
    mask: open ? null : noInput
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-panel"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    Region { id: noInput }

    // Deteccion MPRIS y seleccion automatica del reproductor activo
    readonly property var players: Mpris.players.values
    property int selectedIndex: -1

    readonly property var activePlayer: {
        if (!players || players.length === 0) return null
        if (selectedIndex >= 0 && selectedIndex < players.length) return players[selectedIndex]
        for (let i = 0; i < players.length; i++) {
            if (players[i].playbackState === MprisPlaybackState.Playing) return players[i]
        }
        return players[0]
    }

    function nextPlayer() {
        if (!players || players.length <= 1) return
        let cur = selectedIndex
        if (cur === -1) {
            for (let i = 0; i < players.length; i++) {
                if (players[i] === activePlayer) { cur = i; break }
            }
        }
        selectedIndex = (cur + 1) % players.length
    }

    readonly property bool isPlaying: activePlayer?.playbackState === MprisPlaybackState.Playing
    readonly property string title: activePlayer?.trackTitle || "Sin reproduccion"
    readonly property string artist: activePlayer?.trackArtist || "Ninguna pista activa"
    readonly property string artUrl: activePlayer?.trackArtUrl || ""
    readonly property bool hasArt: artUrl !== ""

    readonly property real progressFraction: {
        if (!activePlayer || !activePlayer.length || activePlayer.length <= 0) return 0
        return Math.min(1.0, Math.max(0.0, activePlayer.position / activePlayer.length))
    }

    function formatTime(totalSeconds) {
        if (!totalSeconds || isNaN(totalSeconds) || totalSeconds < 0) return "0:00"
        const m = Math.floor(totalSeconds / 60)
        const s = Math.floor(totalSeconds % 60)
        return `${m}:${s < 10 ? "0" : ""}${s}`
    }

    // Color ambiental adaptativo segun la identidad del reproductor activo
    readonly property color playerAccent: {
        const id = (activePlayer?.identity || "").toLowerCase()
        if (id.includes("spotify")) return "#1DB954"
        if (id.includes("brave")) return "#FF5500"
        if (id.includes("firefox")) return "#FF7139"
        if (id.includes("chrome") || id.includes("chromium")) return "#4285F4"
        if (id.includes("vlc")) return "#FF8800"
        if (id.includes("cider") || id.includes("apple")) return "#FA2D48"
        if (id.includes("youtube")) return "#FF0000"
        return Theme.accent
    }

    // Area externa de descarte al hacer clic fuera de la isla
    MouseArea {
        anchors.fill: parent
        enabled: root.open
        acceptedButtons: Qt.AllButtons
        onClicked: root.dismiss()
    }

    // Contenedor morfico de la tarjeta de la isla dinamica
    Item {
        id: cardContainer
        anchors.horizontalCenter: parent.horizontalCenter
        y: 3 // Alineado exactamente con el offset superior de la isla compacta en la barra

        readonly property real compactWidth: (anchorItem && anchorItem.width > 0) ? anchorItem.width : 220
        readonly property real compactHeight: Theme.capsule
        readonly property real expandedWidth: 420
        readonly property real expandedHeight: 180

        width: compactWidth + (expandedWidth - compactWidth) * root.progress
        height: compactHeight + (expandedHeight - compactHeight) * root.progress

        Rectangle {
            id: card
            anchors.fill: parent
            radius: 12 + (36 - 12) * root.progress
            color: "#08080a"
            border.width: 1
            border.color: Qt.alpha(root.playerAccent, 0.32 * root.progress + 0.12)
            clip: true
            focus: true
            Keys.onEscapePressed: root.dismiss()

            // Soporte de rueda de raton para ajuste rapido de volumen en cualquier parte de la isla
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onWheel: wheel => {
                    if (!root.activePlayer || !root.activePlayer.volumeSupported) return
                    const delta = wheel.angleDelta.y > 0 ? 0.05 : -0.05
                    root.activePlayer.volume = Math.max(0.0, Math.min(1.0, (root.activePlayer.volume ?? 0.5) + delta))
                }
            }

            // Capa 1: Caratula desenfocada / textura ambiental de fondo
            Image {
                anchors.fill: parent
                source: root.artUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                opacity: 0.16 * root.progress
                visible: root.hasArt && status === Image.Ready
            }

            // Capa 2: Degradado adaptativo vertical con el tono del reproductor
            Rectangle {
                anchors.fill: parent
                opacity: root.progress
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: Qt.alpha("#050508", 0.75) }
                    GradientStop { position: 0.50; color: Qt.alpha("#050508", 0.55) }
                    GradientStop { position: 1.0; color: Qt.alpha(root.playerAccent, 0.34) }
                }
            }

            // Capa 3: Resplandor radial inferior (ambient spotlight)
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: -28
                width: parent.width * 0.85
                height: 85
                radius: width / 2
                color: Qt.alpha(root.playerAccent, 0.25 * root.progress)

                SequentialAnimation on opacity {
                    running: root.isPlaying && root.open
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.60; duration: 1600; easing.type: Easing.InOutQuad }
                    NumberAnimation { to: 1.0; duration: 1600; easing.type: Easing.InOutQuad }
                }
            }

            // Capa 4: Contenido de la isla dinamica (fade-in gradual durante expansion)
            Column {
                anchors.fill: parent
                anchors.topMargin: 16
                anchors.bottomMargin: 14
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 12
                opacity: Math.max(0.0, (root.progress - 0.22) / 0.78)

                // --- 1. FILA SUPERIOR: Caratula circular + Titulo/Artista + Badge de fuente ---
                RowLayout {
                    width: parent.width
                    spacing: 14

                    // Caratula circular (52x52, radio 26)
                    Item {
                        Layout.preferredWidth: 52
                        Layout.preferredHeight: 52

                        Rectangle {
                            id: coverMask
                            anchors.fill: parent
                            radius: width / 2
                            visible: false
                            layer.enabled: true
                        }

                        Image {
                            id: expandedCover
                            anchors.fill: parent
                            source: root.artUrl
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            visible: status === Image.Ready && root.hasArt
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                maskEnabled: true
                                maskSource: coverMask
                            }
                        }

                        Icon {
                            anchors.centerIn: parent
                            visible: !expandedCover.visible
                            text: "music_note"
                            font.pixelSize: 22
                            color: root.playerAccent
                        }

                        // Anillo perimetral elegante
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: "transparent"
                            border.width: 1
                            border.color: Qt.alpha("#ffffff", 0.20)
                        }

                        MouseArea {
                            id: coverMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.activePlayer?.togglePlaying()
                        }

                        scale: coverMouse.pressed ? 0.94 : (coverMouse.containsMouse ? 1.05 : 1.0)
                        Behavior on scale { Anim { duration: 120 } }
                    }

                    // Informacion de pista: Titulo en negrita y Artista
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 3

                        StyledText {
                            Layout.fillWidth: true
                            text: root.title
                            font.bold: true
                            font.pixelSize: 15
                            color: "#ffffff"
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: root.artist
                            font.weight: Font.Medium
                            font.pixelSize: 12
                            color: Qt.alpha("#ffffff", 0.65)
                            elide: Text.ElideRight
                        }
                    }

                    // Badge de fuente interactivo con ecualizador animado
                    Rectangle {
                        id: badgeRect
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        radius: 16
                        color: Qt.alpha(root.playerAccent, 0.18)
                        border.width: 1
                        border.color: Qt.alpha(root.playerAccent, 0.40)

                        Row {
                            anchors.centerIn: parent
                            spacing: 2
                            visible: root.isPlaying

                            Rectangle {
                                width: 2.5; height: 6; radius: 1.25; color: root.playerAccent
                                anchors.bottom: parent.bottom
                                SequentialAnimation on height {
                                    running: root.isPlaying && root.open
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 12; duration: 320; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 4; duration: 360; easing.type: Easing.InOutSine }
                                }
                            }
                            Rectangle {
                                width: 2.5; height: 10; radius: 1.25; color: root.playerAccent
                                anchors.bottom: parent.bottom
                                SequentialAnimation on height {
                                    running: root.isPlaying && root.open
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 4; duration: 400; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 13; duration: 340; easing.type: Easing.InOutSine }
                                }
                            }
                            Rectangle {
                                width: 2.5; height: 7; radius: 1.25; color: root.playerAccent
                                anchors.bottom: parent.bottom
                                SequentialAnimation on height {
                                    running: root.isPlaying && root.open
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 11; duration: 290; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 5; duration: 420; easing.type: Easing.InOutSine }
                                }
                            }
                        }

                        Icon {
                            anchors.centerIn: parent
                            visible: !root.isPlaying
                            text: "play_arrow"
                            font.pixelSize: 16
                            color: root.playerAccent
                        }

                        MouseArea {
                            id: badgeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.nextPlayer()
                        }

                        scale: badgeMouse.containsMouse ? 1.08 : 1.0
                        Behavior on scale { Anim { duration: 120 } }

                        Tooltip {
                            target: badgeRect
                            text: root.players.length > 1
                                ? `Fuente: ${root.activePlayer?.identity || "Reproductor"} (Clic para cambiar a ${root.players[(root.selectedIndex + 1) % root.players.length]?.identity})`
                                : (root.activePlayer?.identity || "Reproductor")
                            hovered: badgeMouse.containsMouse
                        }
                    }
                }

                // --- 2. FILA MEDIA: Linea de tiempo (Scrubber) y tiempos numericos ---
                Column {
                    width: parent.width
                    spacing: 4

                    Item {
                        id: scrubber
                        width: parent.width
                        height: 16

                        Rectangle {
                            id: scrubberTrack
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: 4
                            radius: 2
                            color: Qt.alpha("#ffffff", 0.20)

                            Rectangle {
                                height: parent.height
                                radius: parent.radius
                                width: parent.width * root.progressFraction
                                color: "#ffffff"
                            }
                        }

                        // Manija circular blanca (Thumb knob)
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            x: Math.max(0, Math.min(scrubber.width - width, (scrubber.width * root.progressFraction) - (width / 2)))
                            width: scrubMouse.containsMouse || scrubMouse.pressed ? 12 : 9
                            height: width
                            radius: width / 2
                            color: "#ffffff"
                            scale: scrubMouse.pressed ? 1.25 : 1.0
                            Behavior on scale { Anim { duration: 100 } }
                        }

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

                    // Tiempos transcurrido y restante
                    RowLayout {
                        width: parent.width

                        StyledText {
                            text: root.formatTime(root.activePlayer?.position)
                            font.family: Theme.font
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            color: Qt.alpha("#ffffff", 0.60)
                        }

                        Item { Layout.fillWidth: true }

                        StyledText {
                            text: "-" + root.formatTime((root.activePlayer?.length ?? 0) - (root.activePlayer?.position ?? 0))
                            font.family: Theme.font
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            color: Qt.alpha("#ffffff", 0.60)
                        }
                    }
                }

                // --- 3. FILA INFERIOR: Controles de reproduccion ---
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 26

                    // Shuffle
                    Rectangle {
                        width: 32
                        height: 32
                        radius: 16
                        anchors.verticalCenter: parent.verticalCenter
                        color: shuffleHover.containsMouse ? Qt.alpha("#ffffff", 0.10) : "transparent"

                        Icon {
                            anchors.centerIn: parent
                            text: "shuffle"
                            font.pixelSize: 20
                            color: root.activePlayer?.shuffle ? root.playerAccent : Qt.alpha("#ffffff", 0.60)
                        }

                        MouseArea {
                            id: shuffleHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.activePlayer && root.activePlayer.shuffleSupported) {
                                    root.activePlayer.shuffle = !root.activePlayer.shuffle
                                }
                            }
                        }
                    }

                    // Pista Anterior
                    Rectangle {
                        width: 36
                        height: 36
                        radius: 18
                        anchors.verticalCenter: parent.verticalCenter
                        color: prevHover.pressed ? Qt.alpha("#ffffff", 0.20) : (prevHover.containsMouse ? Qt.alpha("#ffffff", 0.10) : "transparent")
                        scale: prevHover.pressed ? 0.90 : (prevHover.containsMouse ? 1.08 : 1.0)
                        Behavior on scale { Anim { duration: 100 } }

                        Icon {
                            anchors.centerIn: parent
                            text: "skip_previous"
                            font.pixelSize: 26
                            color: root.activePlayer?.canGoPrevious ? "#ffffff" : Qt.alpha("#ffffff", 0.40)
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

                    // Boton Hero Central: Circulo blanco solido con icono negro de Play/Pausa
                    Rectangle {
                        width: 46
                        height: 46
                        radius: 23
                        anchors.verticalCenter: parent.verticalCenter
                        color: "#ffffff"
                        scale: playHover.pressed ? 0.92 : (playHover.containsMouse ? 1.06 : 1.0)
                        Behavior on scale { Anim { duration: 120 } }

                        Icon {
                            anchors.centerIn: parent
                            text: root.isPlaying ? "pause" : "play_arrow"
                            font.pixelSize: 28
                            color: "#000000"
                        }

                        MouseArea {
                            id: playHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.activePlayer?.togglePlaying()
                        }
                    }

                    // Pista Siguiente
                    Rectangle {
                        width: 36
                        height: 36
                        radius: 18
                        anchors.verticalCenter: parent.verticalCenter
                        color: nextHover.pressed ? Qt.alpha("#ffffff", 0.20) : (nextHover.containsMouse ? Qt.alpha("#ffffff", 0.10) : "transparent")
                        scale: nextHover.pressed ? 0.90 : (nextHover.containsMouse ? 1.08 : 1.0)
                        Behavior on scale { Anim { duration: 100 } }

                        Icon {
                            anchors.centerIn: parent
                            text: "skip_next"
                            font.pixelSize: 26
                            color: root.activePlayer?.canGoNext ? "#ffffff" : Qt.alpha("#ffffff", 0.40)
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

                    // Repetir / Bucle
                    Rectangle {
                        width: 32
                        height: 32
                        radius: 16
                        anchors.verticalCenter: parent.verticalCenter
                        color: repeatHover.containsMouse ? Qt.alpha("#ffffff", 0.10) : "transparent"

                        Icon {
                            anchors.centerIn: parent
                            text: root.activePlayer?.loopState === MprisLoopState.Track ? "repeat_one" : "repeat"
                            font.pixelSize: 20
                            color: root.activePlayer?.loopState !== MprisLoopState.None ? root.playerAccent : Qt.alpha("#ffffff", 0.60)
                        }

                        MouseArea {
                            id: repeatHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!root.activePlayer) return
                                if (root.activePlayer.loopState === MprisLoopState.None) {
                                    root.activePlayer.loopState = MprisLoopState.Playlist
                                } else if (root.activePlayer.loopState === MprisLoopState.Playlist) {
                                    root.activePlayer.loopState = MprisLoopState.Track
                                } else {
                                    root.activePlayer.loopState = MprisLoopState.None
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
