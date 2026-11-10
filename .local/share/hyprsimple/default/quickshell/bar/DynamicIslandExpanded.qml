import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Mpris
import qs.theme
import qs.components

// Isla dinamica expandida (Dynamic Island) estilo iOS:
// - Despliegue ultrarrapido (180ms) con curva elastica tipo Apple.
// - Fondo solido negro azabache (#0a0b0e) con iluminacion ambiental inferior difusa.
// - Caratula circular con mascara acelerada por GPU (MultiEffect).
// - Tipografia moderna sans-serif (Noto Sans / Cantarell) de alta definicion.
// - Linea de tiempo horizontal unificada (tiempo transcurrido, barra y tiempo restante en una sola fila).
// - Boton circular blanco solido con barras de pausa geometricas puras (evita fallos de fuentes tipo '00').
PanelWindow {
    id: root

    required property var bar
    property Item anchorItem: null
    readonly property bool open: bar.openPanel === "media"
    property real progress: 0.0

    // Animacion de apertura ultrarrapida y elastica estilo iOS
    NumberAnimation {
        id: opening
        target: root
        property: "progress"
        to: 1.0
        duration: 180
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.1, 0.9, 0.2, 1.0]
    }

    // Animacion de cierre instantanea y limpia
    NumberAnimation {
        id: closing
        target: root
        property: "progress"
        to: 0.0
        duration: 140
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.25, 0.1, 0.25, 1.0]
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

    // Deteccion MPRIS y seleccion reactiva de fuente
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

    // Tono ambiental reactivo al reproductor
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

    // Descarte al hacer clic fuera del rectangulo de la isla
    MouseArea {
        anchors.fill: parent
        enabled: root.open
        acceptedButtons: Qt.AllButtons
        onClicked: root.dismiss()
    }

    // Contenedor de la tarjeta de la Dynamic Island
    Item {
        id: cardContainer
        anchors.horizontalCenter: parent.horizontalCenter
        y: 3

        readonly property real compactWidth: (anchorItem && anchorItem.width > 0) ? anchorItem.width : 220
        readonly property real compactHeight: Theme.capsule
        readonly property real expandedWidth: 380
        readonly property real expandedHeight: 154

        width: compactWidth + (expandedWidth - compactWidth) * root.progress
        height: compactHeight + (expandedHeight - compactHeight) * root.progress

        Rectangle {
            id: card
            anchors.fill: parent
            radius: 12 + (32 - 12) * root.progress
            color: "#0a0b0e" // Fondo 100% solido negro profundo para no transparentar ventanas
            border.width: 1
            border.color: Qt.alpha(root.playerAccent, 0.35 * root.progress + 0.10)
            clip: true
            focus: true
            Keys.onEscapePressed: root.dismiss()

            // Soporte de rueda de raton para ajuste de volumen
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onWheel: wheel => {
                    if (!root.activePlayer || !root.activePlayer.volumeSupported) return
                    const delta = wheel.angleDelta.y > 0 ? 0.05 : -0.05
                    root.activePlayer.volume = Math.max(0.0, Math.min(1.0, (root.activePlayer.volume ?? 0.5) + delta))
                }
            }

            // Resplandor ambiental difuso inferior (sin formas geometricas cortadas)
            Rectangle {
                anchors.fill: parent
                opacity: root.progress
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.45; color: "transparent" }
                    GradientStop { position: 0.80; color: Qt.alpha(root.playerAccent, 0.10) }
                    GradientStop { position: 1.0; color: Qt.alpha(root.playerAccent, 0.28) }
                }
            }

            // Contenido interior de la isla
            Column {
                anchors.fill: parent
                anchors.topMargin: 15
                anchors.bottomMargin: 14
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                spacing: 12
                opacity: Math.min(1.0, root.progress * 1.6)

                // --- 1. FILA SUPERIOR: Caratula circular + Titulo/Artista + Badge de fuente ---
                RowLayout {
                    width: parent.width
                    spacing: 12

                    // Caratula circular pura (46x46, radio 23)
                    Item {
                        Layout.preferredWidth: 46
                        Layout.preferredHeight: 46

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
                            font.pixelSize: 20
                            color: root.playerAccent
                        }

                        // Anillo exterior suave
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: "transparent"
                            border.width: 1
                            border.color: Qt.alpha("#ffffff", 0.18)
                        }

                        MouseArea {
                            id: coverMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.activePlayer?.togglePlaying()
                        }

                        scale: coverMouse.pressed ? 0.94 : (coverMouse.containsMouse ? 1.05 : 1.0)
                        Behavior on scale { Anim { duration: 100 } }
                    }

                    // Informacion de pista: Tipografia limpia sans-serif (no monospace)
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            text: root.title
                            font.family: "Noto Sans, Cantarell, sans-serif"
                            font.bold: true
                            font.pixelSize: 14
                            color: "#ffffff"
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: root.artist
                            font.family: "Noto Sans, Cantarell, sans-serif"
                            font.weight: Font.Normal
                            font.pixelSize: 11
                            color: Qt.alpha("#ffffff", 0.55)
                            elide: Text.ElideRight
                        }
                    }

                    // Badge de fuente interactivo con ecualizador animado
                    Rectangle {
                        id: badgeRect
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30
                        radius: 15
                        color: Qt.alpha(root.playerAccent, 0.16)
                        border.width: 1
                        border.color: Qt.alpha(root.playerAccent, 0.35)

                        Row {
                            anchors.centerIn: parent
                            spacing: 2
                            visible: root.isPlaying

                            Rectangle {
                                width: 2.2; height: 5; radius: 1.1; color: root.playerAccent
                                anchors.bottom: parent.bottom
                                SequentialAnimation on height {
                                    running: root.isPlaying && root.open
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 11; duration: 320; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 4; duration: 360; easing.type: Easing.InOutSine }
                                }
                            }
                            Rectangle {
                                width: 2.2; height: 9; radius: 1.1; color: root.playerAccent
                                anchors.bottom: parent.bottom
                                SequentialAnimation on height {
                                    running: root.isPlaying && root.open
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 4; duration: 400; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 12; duration: 340; easing.type: Easing.InOutSine }
                                }
                            }
                            Rectangle {
                                width: 2.2; height: 6; radius: 1.1; color: root.playerAccent
                                anchors.bottom: parent.bottom
                                SequentialAnimation on height {
                                    running: root.isPlaying && root.open
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 10; duration: 290; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 5; duration: 420; easing.type: Easing.InOutSine }
                                }
                            }
                        }

                        Icon {
                            anchors.centerIn: parent
                            visible: !root.isPlaying
                            text: "play_arrow"
                            font.pixelSize: 15
                            color: root.playerAccent
                        }

                        MouseArea {
                            id: badgeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.nextPlayer()
                        }

                        Tooltip {
                            target: badgeRect
                            text: root.players.length > 1
                                ? `Fuente: ${root.activePlayer?.identity || "Reproductor"} (Clic para cambiar a ${root.players[(root.selectedIndex + 1) % root.players.length]?.identity})`
                                : (root.activePlayer?.identity || "Reproductor")
                            hovered: badgeMouse.containsMouse
                        }
                    }
                }

                // --- 2. FILA MEDIA: Linea de tiempo horizontal unificada ---
                RowLayout {
                    width: parent.width
                    spacing: 8

                    StyledText {
                        text: root.formatTime(root.activePlayer?.position)
                        font.family: "Noto Sans, Cantarell, sans-serif"
                        font.pixelSize: 10
                        font.weight: Font.Medium
                        color: Qt.alpha("#ffffff", 0.50)
                    }

                    Item {
                        id: scrubber
                        Layout.fillWidth: true
                        height: 16

                        Rectangle {
                            id: scrubberTrack
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: 3
                            radius: 1.5
                            color: Qt.alpha("#ffffff", 0.18)

                            Rectangle {
                                height: parent.height
                                radius: parent.radius
                                width: parent.width * root.progressFraction
                                color: "#ffffff"
                            }
                        }

                        // Knob circular blanco
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            x: Math.max(0, Math.min(scrubber.width - width, (scrubber.width * root.progressFraction) - (width / 2)))
                            width: scrubMouse.containsMouse || scrubMouse.pressed ? 10 : 8
                            height: width
                            radius: width / 2
                            color: "#ffffff"
                            scale: scrubMouse.pressed ? 1.25 : 1.0
                            Behavior on scale { Anim { duration: 80 } }
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

                    StyledText {
                        text: "-" + root.formatTime((root.activePlayer?.length ?? 0) - (root.activePlayer?.position ?? 0))
                        font.family: "Noto Sans, Cantarell, sans-serif"
                        font.pixelSize: 10
                        font.weight: Font.Medium
                        color: Qt.alpha("#ffffff", 0.50)
                    }
                }

                // --- 3. FILA INFERIOR: Controles de reproduccion ---
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 28

                    // Shuffle
                    Rectangle {
                        width: 30
                        height: 30
                        radius: 15
                        anchors.verticalCenter: parent.verticalCenter
                        color: shuffleHover.containsMouse ? Qt.alpha("#ffffff", 0.10) : "transparent"

                        Icon {
                            anchors.centerIn: parent
                            text: "shuffle"
                            font.pixelSize: 17
                            color: root.activePlayer?.shuffle ? root.playerAccent : Qt.alpha("#ffffff", 0.50)
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
                        width: 34
                        height: 34
                        radius: 17
                        anchors.verticalCenter: parent.verticalCenter
                        color: prevHover.pressed ? Qt.alpha("#ffffff", 0.18) : (prevHover.containsMouse ? Qt.alpha("#ffffff", 0.08) : "transparent")
                        scale: prevHover.pressed ? 0.90 : (prevHover.containsMouse ? 1.08 : 1.0)
                        Behavior on scale { Anim { duration: 80 } }

                        Icon {
                            anchors.centerIn: parent
                            text: "skip_previous"
                            font.pixelSize: 24
                            color: root.activePlayer?.canGoPrevious ? "#ffffff" : Qt.alpha("#ffffff", 0.35)
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

                    // Boton Hero Central: Circulo blanco solido con barras de pausa geometricas puras (aspecto iOS autentico)
                    Rectangle {
                        width: 42
                        height: 42
                        radius: 21
                        anchors.verticalCenter: parent.verticalCenter
                        color: "#ffffff"
                        scale: playHover.pressed ? 0.92 : (playHover.containsMouse ? 1.05 : 1.0)
                        Behavior on scale { Anim { duration: 100 } }

                        // Barras de pausa geometricas puras (garantiza aspecto iOS, nunca '00')
                        Row {
                            anchors.centerIn: parent
                            spacing: 4
                            visible: root.isPlaying

                            Rectangle {
                                width: 3.5
                                height: 14
                                radius: 1.5
                                color: "#000000"
                            }
                            Rectangle {
                                width: 3.5
                                height: 14
                                radius: 1.5
                                color: "#000000"
                            }
                        }

                        // Icono de play centrado opticamente
                        Icon {
                            anchors.centerIn: parent
                            anchors.horizontalCenterOffset: 1
                            visible: !root.isPlaying
                            text: "play_arrow"
                            font.pixelSize: 24
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
                        width: 34
                        height: 34
                        radius: 17
                        anchors.verticalCenter: parent.verticalCenter
                        color: nextHover.pressed ? Qt.alpha("#ffffff", 0.18) : (nextHover.containsMouse ? Qt.alpha("#ffffff", 0.08) : "transparent")
                        scale: nextHover.pressed ? 0.90 : (nextHover.containsMouse ? 1.08 : 1.0)
                        Behavior on scale { Anim { duration: 80 } }

                        Icon {
                            anchors.centerIn: parent
                            text: "skip_next"
                            font.pixelSize: 24
                            color: root.activePlayer?.canGoNext ? "#ffffff" : Qt.alpha("#ffffff", 0.35)
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

                    // Repetir
                    Rectangle {
                        width: 30
                        height: 30
                        radius: 15
                        anchors.verticalCenter: parent.verticalCenter
                        color: repeatHover.containsMouse ? Qt.alpha("#ffffff", 0.10) : "transparent"

                        Icon {
                            anchors.centerIn: parent
                            text: root.activePlayer?.loopState === MprisLoopState.Track ? "repeat_one" : "repeat"
                            font.pixelSize: 17
                            color: root.activePlayer?.loopState !== MprisLoopState.None ? root.playerAccent : Qt.alpha("#ffffff", 0.50)
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
