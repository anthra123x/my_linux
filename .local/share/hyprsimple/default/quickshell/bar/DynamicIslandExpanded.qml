import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.theme
import qs.components

// Isla dinamica expandida (Dynamic Island) fiel a iOS:
// - Morfismo rapido y elastico (180ms) con curva Apple [0.16, 1.0, 0.3, 1.0].
// - Fondo negro azabache solido (#000000) sin transparencias indeseadas ni bordes toscos.
// - Iluminacion ambiental dinamica extraida en tiempo real de la caratula de la pista activa.
// - Resplandor difuso suave mediante desenfoque acelerado por GPU (MultiEffect), eliminando cortes rectangulares en las esquinas.
// - Caratula circular perfecta, tipografia moderna sans-serif y scrubber unificado en una sola fila.
// - Boton Play/Pausa hero blanco solido con barras de pausa geometricas puras (aspecto exacto a iOS).
PanelWindow {
    id: root

    required property var bar
    property Item anchorItem: null
    readonly property bool open: bar.openPanel === "media"
    property real progress: 0.0

    // Animacion de expansion rapida y elastica tipo iOS
    NumberAnimation {
        id: opening
        target: root
        property: "progress"
        to: 1.0
        duration: 180
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.16, 1.0, 0.3, 1.0]
    }

    // Animacion de contraccion instantanea
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

    // Deteccion MPRIS
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

    // Color ambiental extraido directamente de la caratula de la cancion
    property color coverAccent: "#7aa2f7"
    Behavior on coverAccent { ColorAnimation { duration: 350 } }

    Process {
        id: colorExtractor
        command: ["/home/omicron/.local/bin/dynamic-island-color.py", root.artUrl]
        stdout: SplitParser {
            onRead: data => {
                const hex = data.trim()
                if (hex.startsWith("#") && hex.length === 7) {
                    root.coverAccent = hex
                }
            }
        }
    }

    onArtUrlChanged: {
        if (artUrl !== "") colorExtractor.running = true
    }

    Component.onCompleted: {
        if (artUrl !== "") colorExtractor.running = true
    }

    // Descarte al hacer clic fuera del rectangulo de la isla
    MouseArea {
        anchors.fill: parent
        enabled: root.open
        acceptedButtons: Qt.AllButtons
        onClicked: root.dismiss()
    }

    // Contenedor morfico de la tarjeta
    Item {
        id: cardContainer
        anchors.horizontalCenter: parent.horizontalCenter
        y: 4

        readonly property real compactWidth: (anchorItem && anchorItem.width > 0) ? anchorItem.width : 220
        readonly property real compactHeight: Theme.capsule
        readonly property real expandedWidth: 400
        readonly property real expandedHeight: 162

        width: compactWidth + (expandedWidth - compactWidth) * root.progress
        height: compactHeight + (expandedHeight - compactHeight) * root.progress

        // Tarjeta principal con radio de curvatura suave tipo squircle
        Rectangle {
            id: card
            anchors.fill: parent
            radius: 12 + (38 - 12) * root.progress
            color: "#000000" // 100% negro azabache absoluto
            border.width: 1
            border.color: Qt.alpha("#ffffff", 0.08)
            clip: true
            focus: true
            Keys.onEscapePressed: root.dismiss()

            // Control de volumen con rueda de raton
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onWheel: wheel => {
                    if (!root.activePlayer || !root.activePlayer.volumeSupported) return
                    const delta = wheel.angleDelta.y > 0 ? 0.05 : -0.05
                    root.activePlayer.volume = Math.max(0.0, Math.min(1.0, (root.activePlayer.volume ?? 0.5) + delta))
                }
            }

            // Capa 1: Foco ambiental difuso en la zona inferior (desenfoque optico acelerado)
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: -30
                width: parent.width * 0.70
                height: 80
                radius: width / 2
                color: root.coverAccent
                opacity: root.progress * (root.isPlaying ? 0.28 : 0.14)
                layer.enabled: true
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blur: 1.0
                    blurMax: 32
                }
            }

            // Capa 2: Gradiente vertical ambiental restringido con el radio exacto de la tarjeta
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                opacity: root.progress
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.40; color: "transparent" }
                    GradientStop { position: 0.75; color: Qt.alpha(root.coverAccent, 0.08) }
                    GradientStop { position: 1.0; color: Qt.alpha(root.coverAccent, 0.22) }
                }
            }

            // Capa 3: Contenido de la isla
            Column {
                anchors.fill: parent
                anchors.topMargin: 16
                anchors.bottomMargin: 14
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 12
                opacity: Math.min(1.0, root.progress * 1.6)

                // --- 1. FILA SUPERIOR: Caratula circular + Titulo/Artista + Accion (+) ---
                RowLayout {
                    width: parent.width
                    spacing: 14

                    // Caratula circular perfecta (50x50, radio 25)
                    Item {
                        Layout.preferredWidth: 50
                        Layout.preferredHeight: 50

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
                            color: root.coverAccent
                        }

                        // Anillo perimetral sutil
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: "transparent"
                            border.width: 1
                            border.color: Qt.alpha("#ffffff", 0.15)
                        }

                        MouseArea {
                            id: coverMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.activePlayer?.togglePlaying()
                        }

                        scale: coverMouse.pressed ? 0.94 : (coverMouse.containsMouse ? 1.04 : 1.0)
                        Behavior on scale { Anim { duration: 90 } }
                    }

                    // Informacion de pista: Titulo y Artista en sans-serif moderna
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            text: root.title
                            font.family: "Noto Sans, Cantarell, sans-serif"
                            font.bold: true
                            font.pixelSize: 15
                            color: "#ffffff"
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: root.artist
                            font.family: "Noto Sans, Cantarell, sans-serif"
                            font.weight: Font.Normal
                            font.pixelSize: 12
                            color: Qt.alpha("#ffffff", 0.60)
                            elide: Text.ElideRight
                        }
                    }

                    // Boton de accion circular (+) fiel a la captura de referencia
                    Rectangle {
                        id: actionBtn
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30
                        radius: 15
                        color: actionHover.containsMouse ? Qt.alpha("#ffffff", 0.12) : "transparent"
                        border.width: 1.5
                        border.color: Qt.alpha("#ffffff", 0.45)

                        Icon {
                            anchors.centerIn: parent
                            text: "add"
                            font.pixelSize: 18
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: actionHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.nextPlayer()
                        }

                        scale: actionHover.pressed ? 0.92 : (actionHover.containsMouse ? 1.06 : 1.0)
                        Behavior on scale { Anim { duration: 90 } }

                        Tooltip {
                            target: actionBtn
                            text: root.players.length > 1
                                ? `Fuente: ${root.activePlayer?.identity || "Reproductor"} (Clic para cambiar a ${root.players[(root.selectedIndex + 1) % root.players.length]?.identity})`
                                : (root.activePlayer?.identity || "Reproductor")
                            hovered: actionHover.containsMouse
                        }
                    }
                }

                // --- 2. FILA MEDIA: Scrubber horizontal unificado ---
                RowLayout {
                    width: parent.width
                    spacing: 10

                    StyledText {
                        text: root.formatTime(root.activePlayer?.position)
                        font.family: "Noto Sans, Cantarell, sans-serif"
                        font.pixelSize: 11
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

                        // Knob circular blanco exacto a iOS
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
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        color: Qt.alpha("#ffffff", 0.50)
                    }
                }

                // --- 3. FILA INFERIOR: Controles de reproduccion simetricos ---
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 30

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
                            font.pixelSize: 19
                            color: root.activePlayer?.shuffle ? root.coverAccent : Qt.alpha("#ffffff", 0.60)
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
                        color: prevHover.pressed ? Qt.alpha("#ffffff", 0.18) : (prevHover.containsMouse ? Qt.alpha("#ffffff", 0.08) : "transparent")
                        scale: prevHover.pressed ? 0.90 : (prevHover.containsMouse ? 1.08 : 1.0)
                        Behavior on scale { Anim { duration: 80 } }

                        Icon {
                            anchors.centerIn: parent
                            text: "skip_previous"
                            font.pixelSize: 26
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

                    // Boton Hero Central: Circulo blanco solido con barras de pausa geometricas puras
                    Rectangle {
                        width: 46
                        height: 46
                        radius: 23
                        anchors.verticalCenter: parent.verticalCenter
                        color: "#ffffff"
                        scale: playHover.pressed ? 0.92 : (playHover.containsMouse ? 1.05 : 1.0)
                        Behavior on scale { Anim { duration: 90 } }

                        // Barras de pausa geometricas puras (aspecto exacto iOS, nunca '00')
                        Row {
                            anchors.centerIn: parent
                            spacing: 4.5
                            visible: root.isPlaying

                            Rectangle {
                                width: 4
                                height: 16
                                radius: 2
                                color: "#000000"
                            }
                            Rectangle {
                                width: 4
                                height: 16
                                radius: 2
                                color: "#000000"
                            }
                        }

                        // Icono play centrado opticamente
                        Icon {
                            anchors.centerIn: parent
                            anchors.horizontalCenterOffset: 1
                            visible: !root.isPlaying
                            text: "play_arrow"
                            font.pixelSize: 26
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
                        color: nextHover.pressed ? Qt.alpha("#ffffff", 0.18) : (nextHover.containsMouse ? Qt.alpha("#ffffff", 0.08) : "transparent")
                        scale: nextHover.pressed ? 0.90 : (nextHover.containsMouse ? 1.08 : 1.0)
                        Behavior on scale { Anim { duration: 80 } }

                        Icon {
                            anchors.centerIn: parent
                            text: "skip_next"
                            font.pixelSize: 26
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
                        width: 32
                        height: 32
                        radius: 16
                        anchors.verticalCenter: parent.verticalCenter
                        color: repeatHover.containsMouse ? Qt.alpha("#ffffff", 0.10) : "transparent"

                        Icon {
                            anchors.centerIn: parent
                            text: root.activePlayer?.loopState === MprisLoopState.Track ? "repeat_one" : "repeat"
                            font.pixelSize: 19
                            color: root.activePlayer?.loopState !== MprisLoopState.None ? root.coverAccent : Qt.alpha("#ffffff", 0.60)
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
