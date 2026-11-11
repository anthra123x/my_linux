import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.theme
import qs.components

// Isla dinamica expandida (Dynamic Island) unificada segun Apple macOS / iOS:
// - Morfismo continuo y elastico (220ms) con curva Apple [0.16, 1.0, 0.3, 1.0].
// - Fondo negro azabache solido (#000000) con radio squircle y borde translucido.
// - Soporta modo multimedia ("media") y modo calendario reposo ("calendar") dentro del mismo contenedor morfico.
// - Cross-fade interno impecable: la vista compacta se desvanece suavemente en el primer tercio mientras
//   la vista expandida escala y adquiere opacidad sin recortar elementos visuales.
// - Iluminacion ambiental dinamica extraida de la caratula o adaptativa de calendario mediante MultiEffect GPU.
PanelWindow {
    id: root

    required property var bar
    property Item anchorItem: null

    readonly property bool isMedia: bar.openPanel === "media"
    readonly property bool isCalendar: bar.openPanel === "calendar"
    readonly property bool open: isMedia || isCalendar
    property real progress: 0.0

    // Animacion de apertura fluida con fisica Apple Fluid
    NumberAnimation {
        id: opening
        target: root
        property: "progress"
        to: 1.0
        duration: 220
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.16, 1, 0.3, 1, 1, 1]
    }

    // Animacion de cierre instantaneo
    NumberAnimation {
        id: closing
        target: root
        property: "progress"
        to: 0.0
        duration: 170
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.38, 0.0, 0.20, 1.0, 1, 1]
    }

    onOpenChanged: {
        if (open) {
            if (isCalendar) showToday()
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
    color: "transparent"
    mask: open ? null : noInput
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-panel"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    Region { id: noInput }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // --- LOGICA DE CALENDARIO INTEGRADO ---
    property int calYear: 0
    property int calMonth: 0
    readonly property var weekLocale: Qt.locale("en_GB")
    property real calWheelDelta: 0

    function showToday() {
        const d = (clock.date && !isNaN(clock.date.getTime())) ? clock.date : new Date()
        calYear = d.getFullYear()
        calMonth = d.getMonth()
    }

    function applyMonth(delta) {
        const d = new Date(calYear, calMonth + delta, 1)
        calYear = d.getFullYear()
        calMonth = d.getMonth()
    }

    Component.onCompleted: {
        showToday()
        if (artUrl !== "") colorExtractor.running = true
    }

    // --- DETECCION Y CONTROL MPRIS ---
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

    // Descarte al hacer clic fuera del rectangulo de la isla
    MouseArea {
        anchors.fill: parent
        enabled: root.open
        acceptedButtons: Qt.AllButtons
        onClicked: root.dismiss()
    }

    // --- CONTENEDOR MORFICO PRINCIPAL ---
    Item {
        id: cardContainer
        anchors.horizontalCenter: parent.horizontalCenter
        y: 4 // Exactamente alineado con la isla compacta de la barra superior

        // Geometria compacta de partida
        readonly property real compactWidth: (anchorItem && anchorItem.width > 0) ? anchorItem.width : (root.isMedia ? 240 : 150)
        readonly property real compactHeight: Theme.capsule // 30 px

        // Geometria objetivo expandida segun el modo
        readonly property real targetExpandedWidth: root.isMedia ? 400 : 330
        readonly property real targetExpandedHeight: root.isMedia ? 165 : 288
        readonly property real targetExpandedRadius: root.isMedia ? 36 : 32

        property real morphWidth: targetExpandedWidth
        property real morphHeight: targetExpandedHeight
        property real morphRadius: targetExpandedRadius

        Behavior on morphWidth { NumberAnimation { duration: 180; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.16, 1, 0.3, 1, 1, 1] } }
        Behavior on morphHeight { NumberAnimation { duration: 180; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.16, 1, 0.3, 1, 1, 1] } }
        Behavior on morphRadius { NumberAnimation { duration: 180; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.16, 1, 0.3, 1, 1, 1] } }

        // Interpolacion sincronizada de escala y bordes
        width: compactWidth + (morphWidth - compactWidth) * root.progress
        height: compactHeight + (morphHeight - compactHeight) * root.progress
        readonly property real cornerRadius: (compactHeight / 2) + (morphRadius - (compactHeight / 2)) * root.progress

        // Tarjeta de hardware negra azabache solida
        Rectangle {
            id: card
            anchors.fill: parent
            radius: cardContainer.cornerRadius
            color: "#000000"
            border.width: 1
            border.color: Qt.alpha("#ffffff", 0.08)
            clip: true
            focus: true
            Keys.onEscapePressed: root.dismiss()

            // Manejo de rueda de raton (volumen en multimedia, meses en calendario)
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onWheel: wheel => {
                    if (root.isMedia) {
                        if (!root.activePlayer || !root.activePlayer.volumeSupported) return
                        const delta = wheel.angleDelta.y > 0 ? 0.05 : -0.05
                        root.activePlayer.volume = Math.max(0.0, Math.min(1.0, (root.activePlayer.volume ?? 0.5) + delta))
                    } else if (root.isCalendar) {
                        root.calWheelDelta += wheel.angleDelta.y
                        if (Math.abs(root.calWheelDelta) < 120) return
                        root.applyMonth(root.calWheelDelta > 0 ? -1 : 1)
                        root.calWheelDelta = 0
                    }
                }
            }

            // --- AMBIENTE LUMINOSO 1: Foco inferior difuso para multimedia ---
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: -30
                width: parent.width * 0.70
                height: 80
                radius: width / 2
                color: root.coverAccent
                visible: root.isMedia
                opacity: root.progress * (root.isPlaying ? 0.28 : 0.14)
                layer.enabled: true
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blur: 1.0
                    blurMax: 32
                }
            }

            // Gradiente vertical restringido al radio de la tarjeta
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                visible: root.isMedia
                opacity: root.progress
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.40; color: "transparent" }
                    GradientStop { position: 0.75; color: Qt.alpha(root.coverAccent, 0.08) }
                    GradientStop { position: 1.0; color: Qt.alpha(root.coverAccent, 0.22) }
                }
            }

            // --- AMBIENTE LUMINOSO 2: Foco superior difuso para calendario ---
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: -20
                width: parent.width * 0.75
                height: 70
                radius: width / 2
                color: "#ff453a"
                visible: root.isCalendar
                opacity: root.progress * 0.14
                layer.enabled: true
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blur: 1.0
                    blurMax: 32
                }
            }

            // =========================================================================
            // CAPA A: VISTA COMPACTA INTERMEDIA (Transicion organica inicial 0.0 -> 0.33)
            // =========================================================================
            Item {
                id: compactOverlay
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: cardContainer.compactHeight
                opacity: Math.max(0.0, 1.0 - root.progress * 3.0)
                visible: opacity > 0.01

                // Reposo compacto (Apple Calendar Badge + Fecha + Hora)
                Row {
                    anchors.centerIn: parent
                    spacing: Theme.sm
                    visible: root.isCalendar

                    Rectangle {
                        width: 16
                        height: 16
                        radius: 3.5
                        color: "#ffffff"
                        clip: true
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            anchors { top: parent.top; left: parent.left; right: parent.right }
                            height: 4.5
                            color: "#ff3b30"
                        }

                        StyledText {
                            anchors {
                                bottom: parent.bottom
                                horizontalCenter: parent.horizontalCenter
                                bottomMargin: 0.5
                            }
                            text: Qt.formatDateTime(clock.date, "d")
                            font.family: "Noto Sans, Cantarell, sans-serif"
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            color: "#000000"
                        }
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Qt.formatDateTime(clock.date, "ddd d MMM")
                        font.family: "Noto Sans, Cantarell, sans-serif"
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        color: "#98989d"
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "•"
                        color: "#48484a"
                        font.pixelSize: 10
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Qt.formatDateTime(clock.date, "HH:mm")
                        font.family: "Noto Sans, Cantarell, sans-serif"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: "#ffffff"
                    }
                }

                // Multimedia compacta (Caratula circular + Metadatos)
                Row {
                    anchors.centerIn: parent
                    spacing: Theme.sm
                    visible: root.isMedia

                    Item {
                        width: 18
                        height: 18
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            id: compactMask
                            anchors.fill: parent
                            radius: width / 2
                            visible: false
                            layer.enabled: true
                        }

                        Image {
                            anchors.fill: parent
                            source: root.artUrl
                            fillMode: Image.PreserveAspectCrop
                            visible: status === Image.Ready && root.hasArt
                            asynchronous: true
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                maskEnabled: true
                                maskSource: compactMask
                            }
                        }

                        Icon {
                            anchors.centerIn: parent
                            visible: !root.hasArt
                            text: "music_note"
                            font.pixelSize: 12
                            color: root.coverAccent
                        }
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            if (!root.title) return "Reproduciendo"
                            const full = root.artist !== "" ? `${root.artist} - ${root.title}` : root.title
                            return full.length > 24 ? full.slice(0, 23) + "…" : full
                        }
                        font.family: "Noto Sans, Cantarell, sans-serif"
                        font.weight: Font.DemiBold
                        font.pixelSize: 11
                        color: "#ffffff"
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "•"
                        color: "#48484a"
                        font.pixelSize: 10
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Qt.formatDateTime(clock.date, "HH:mm")
                        font.family: "Noto Sans, Cantarell, sans-serif"
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        color: "#98989d"
                    }
                }
            }

            // =========================================================================
            // CAPA B: REPRODUCTOR MULTIMEDIA COMPLETO (Modo "media")
            // =========================================================================
            Column {
                id: expandedMediaContent
                anchors.fill: parent
                anchors.topMargin: 16
                anchors.bottomMargin: 14
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 12
                visible: root.isMedia && opacity > 0.01
                opacity: Math.max(0.0, (root.progress - 0.25) / 0.75)
                scale: 0.94 + 0.06 * root.progress

                // 1. Fila superior: Caratula circular + Titulo/Artista + Accion (+)
                RowLayout {
                    width: parent.width
                    spacing: 14

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

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            text: root.title
                            font.family: "Noto Sans, Cantarell, sans-serif"
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            color: "#ffffff"
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: root.artist
                            font.family: "Noto Sans, Cantarell, sans-serif"
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            color: "#98989d"
                            elide: Text.ElideRight
                        }
                    }

                    // Boton circular de accion (+) o cambio de reproductor
                    Rectangle {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        radius: 14
                        color: actionBtnMouse.pressed ? Qt.alpha("#ffffff", 0.18) : (actionBtnMouse.containsMouse ? Qt.alpha("#ffffff", 0.12) : "transparent")
                        border.width: 1
                        border.color: Qt.alpha("#ffffff", 0.20)

                        Icon {
                            anchors.centerIn: parent
                            text: "add"
                            font.pixelSize: 16
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: actionBtnMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.nextPlayer()
                        }

                        scale: actionBtnMouse.pressed ? 0.92 : (actionBtnMouse.containsMouse ? 1.05 : 1.0)
                        Behavior on scale { Anim { duration: 90 } }
                    }
                }

                // 2. Fila Scrubber: Tiempo transcurrido + Barra interactiva + Tiempo restante
                RowLayout {
                    width: parent.width
                    spacing: 10

                    StyledText {
                        text: root.formatTime(root.activePlayer?.position ?? 0)
                        font.family: "Noto Sans, Cantarell, sans-serif"
                        font.pixelSize: 10
                        font.weight: Font.Medium
                        color: "#98989d"
                        Layout.preferredWidth: 32
                        horizontalAlignment: Text.AlignLeft
                    }

                    Item {
                        id: sliderTrack
                        Layout.fillWidth: true
                        Layout.preferredHeight: 18

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: 4
                            radius: 2
                            color: Qt.alpha("#ffffff", 0.18)
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            width: Math.max(4, parent.width * (scrubberMouse.pressed ? scrubberMouse.scrubFraction : root.progressFraction))
                            height: 4
                            radius: 2
                            color: "#ffffff"
                        }

                        Rectangle {
                            x: Math.max(0, Math.min(parent.width - width, (parent.width * (scrubberMouse.pressed ? scrubberMouse.scrubFraction : root.progressFraction)) - width / 2))
                            anchors.verticalCenter: parent.verticalCenter
                            width: scrubberMouse.pressed ? 12 : 8
                            height: width
                            radius: width / 2
                            color: "#ffffff"
                            Behavior on width { Anim { duration: 90 } }
                        }

                        MouseArea {
                            id: scrubberMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            property real scrubFraction: 0

                            onPositionChanged: mouse => {
                                if (pressed && root.activePlayer && root.activePlayer.length > 0) {
                                    scrubFraction = Math.max(0.0, Math.min(1.0, mouse.x / width))
                                }
                            }
                            onPressed: mouse => {
                                if (root.activePlayer && root.activePlayer.length > 0) {
                                    scrubFraction = Math.max(0.0, Math.min(1.0, mouse.x / width))
                                }
                            }
                            onReleased: mouse => {
                                if (root.activePlayer && root.activePlayer.length > 0) {
                                    const targetSec = scrubFraction * root.activePlayer.length
                                    root.activePlayer.position = targetSec
                                }
                            }
                        }
                    }

                    StyledText {
                        text: {
                            if (!root.activePlayer || !root.activePlayer.length) return "-0:00"
                            const rem = root.activePlayer.length - (root.activePlayer.position ?? 0)
                            return "-" + root.formatTime(Math.max(0, rem))
                        }
                        font.family: "Noto Sans, Cantarell, sans-serif"
                        font.pixelSize: 10
                        font.weight: Font.Medium
                        color: "#98989d"
                        Layout.preferredWidth: 36
                        horizontalAlignment: Text.AlignRight
                    }
                }

                // 3. Fila de Controles: Shuffle, Anterior, Boton Hero Central, Siguiente, Repetir
                RowLayout {
                    width: parent.width

                    // Shuffle
                    Item {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32

                        Icon {
                            anchors.centerIn: parent
                            text: "shuffle"
                            font.pixelSize: 18
                            color: root.activePlayer?.shuffle ? root.coverAccent : Qt.alpha("#ffffff", 0.65)
                        }

                        MouseArea {
                            id: shuffleMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (root.activePlayer?.shuffleSupported) root.activePlayer.shuffle = !root.activePlayer.shuffle
                        }

                        scale: shuffleMouse.pressed ? 0.90 : (shuffleMouse.containsMouse ? 1.10 : 1.0)
                        Behavior on scale { Anim { duration: 90 } }
                    }

                    Item { Layout.fillWidth: true }

                    // Anterior
                    Item {
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36

                        Icon {
                            anchors.centerIn: parent
                            text: "skip_previous"
                            font.pixelSize: 24
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: prevTrackMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.activePlayer?.previous()
                        }

                        scale: prevTrackMouse.pressed ? 0.90 : (prevTrackMouse.containsMouse ? 1.10 : 1.0)
                        Behavior on scale { Anim { duration: 90 } }
                    }

                    Item { Layout.preferredWidth: 16 }

                    // Boton Hero Central Play/Pause (blanco solido con barras de pausa geometricas puras)
                    Rectangle {
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 44
                        radius: 22
                        color: "#ffffff"

                        Row {
                            anchors.centerIn: parent
                            spacing: 5
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

                        Icon {
                            anchors.centerIn: parent
                            anchors.horizontalCenterOffset: 1.5
                            visible: !root.isPlaying
                            text: "play_arrow"
                            font.pixelSize: 26
                            color: "#000000"
                        }

                        MouseArea {
                            id: heroPlayMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.activePlayer?.togglePlaying()
                        }

                        scale: heroPlayMouse.pressed ? 0.92 : (heroPlayMouse.containsMouse ? 1.06 : 1.0)
                        Behavior on scale { Anim { duration: 90 } }
                    }

                    Item { Layout.preferredWidth: 16 }

                    // Siguiente
                    Item {
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36

                        Icon {
                            anchors.centerIn: parent
                            text: "skip_next"
                            font.pixelSize: 24
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: nextTrackMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.activePlayer?.next()
                        }

                        scale: nextTrackMouse.pressed ? 0.90 : (nextTrackMouse.containsMouse ? 1.10 : 1.0)
                        Behavior on scale { Anim { duration: 90 } }
                    }

                    Item { Layout.fillWidth: true }

                    // Repetir
                    Item {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32

                        Icon {
                            anchors.centerIn: parent
                            text: "repeat"
                            font.pixelSize: 18
                            color: (root.activePlayer?.loopStatus && root.activePlayer.loopStatus !== MprisLoopStatus.None) ? root.coverAccent : Qt.alpha("#ffffff", 0.65)
                        }

                        MouseArea {
                            id: repeatMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!root.activePlayer || !root.activePlayer.loopStatusSupported) return
                                const cur = root.activePlayer.loopStatus
                                if (cur === MprisLoopStatus.None) root.activePlayer.loopStatus = MprisLoopStatus.Playlist
                                else if (cur === MprisLoopStatus.Playlist) root.activePlayer.loopStatus = MprisLoopStatus.Track
                                else root.activePlayer.loopStatus = MprisLoopStatus.None
                            }
                        }

                        scale: repeatMouse.pressed ? 0.90 : (repeatMouse.containsMouse ? 1.10 : 1.0)
                        Behavior on scale { Anim { duration: 90 } }
                    }
                }
            }

            // =========================================================================
            // CAPA C: CALENDARIO APPLE EXPANDIDO (Modo reposo "calendar")
            // =========================================================================
            Column {
                id: expandedCalendarContent
                anchors.fill: parent
                anchors.topMargin: 16
                anchors.bottomMargin: 14
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                spacing: 8
                visible: root.isCalendar && opacity > 0.01
                opacity: Math.max(0.0, (root.progress - 0.25) / 0.75)
                scale: 0.94 + 0.06 * root.progress

                // 1. Cabecera con fecha Apple y flechas de navegacion de mes
                RowLayout {
                    width: parent.width

                    ColumnLayout {
                        spacing: 1
                        Layout.fillWidth: true

                        StyledText {
                            text: Qt.formatDate(clock.date, "dddd, d MMMM").toUpperCase()
                            font.family: "Noto Sans, Cantarell, sans-serif"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: "#ff453a"
                        }

                        Row {
                            spacing: 8
                            Layout.alignment: Qt.AlignVCenter

                            StyledText {
                                text: root.weekLocale.standaloneMonthName(root.calMonth) + " " + root.calYear
                                font.family: "Noto Sans, Cantarell, sans-serif"
                                font.pixelSize: 17
                                font.weight: Font.Bold
                                color: "#ffffff"

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.showToday()
                                }
                            }

                            // Badge interactivo "Hoy" si se esta viendo otro mes
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.calMonth !== clock.date.getMonth() || root.calYear !== clock.date.getFullYear()
                                implicitHeight: 18
                                implicitWidth: todayBadgeText.implicitWidth + 12
                                radius: 9
                                color: Qt.alpha("#ff453a", 0.18)
                                border.width: 1
                                border.color: Qt.alpha("#ff453a", 0.40)

                                StyledText {
                                    id: todayBadgeText
                                    anchors.centerIn: parent
                                    text: "Hoy"
                                    font.family: "Noto Sans, Cantarell, sans-serif"
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    color: "#ff453a"
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.showToday()
                                }
                            }
                        }
                    }

                    // Navegacion de mes
                    Row {
                        spacing: 6
                        Layout.alignment: Qt.AlignVCenter

                        Rectangle {
                            width: 26
                            height: 26
                            radius: 13
                            color: prevMouse.pressed ? Qt.alpha("#ffffff", 0.20) : (prevMouse.containsMouse ? Qt.alpha("#ffffff", 0.12) : Qt.alpha("#ffffff", 0.06))
                            border.width: 1
                            border.color: Qt.alpha("#ffffff", 0.08)

                            Icon {
                                anchors.centerIn: parent
                                text: "chevron_left"
                                font.pixelSize: 16
                                color: "#ffffff"
                            }

                            MouseArea {
                                id: prevMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.applyMonth(-1)
                            }
                        }

                        Rectangle {
                            width: 26
                            height: 26
                            radius: 13
                            color: nextMouse.pressed ? Qt.alpha("#ffffff", 0.20) : (nextMouse.containsMouse ? Qt.alpha("#ffffff", 0.12) : Qt.alpha("#ffffff", 0.06))
                            border.width: 1
                            border.color: Qt.alpha("#ffffff", 0.08)

                            Icon {
                                anchors.centerIn: parent
                                text: "chevron_right"
                                font.pixelSize: 16
                                color: "#ffffff"
                            }

                            MouseArea {
                                id: nextMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.applyMonth(1)
                            }
                        }
                    }
                }

                // 2. Fila de iniciales de dias de la semana (L M X J V S D)
                DayOfWeekRow {
                    width: 7 * 38
                    anchors.horizontalCenter: parent.horizontalCenter
                    locale: root.weekLocale
                    spacing: 0
                    padding: 0

                    delegate: StyledText {
                        required property string shortName
                        horizontalAlignment: Text.AlignHCenter
                        text: shortName.slice(0, 1).toUpperCase()
                        font.family: "Noto Sans, Cantarell, sans-serif"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: "#86868b"
                    }
                }

                // 3. Cuadricula del mes MonthGrid (ajustada exactamente al alto de 6 filas)
                Item {
                    width: 7 * 38
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: 6 * 31
                    clip: true

                    WheelHandler {
                        onWheel: event => {
                            root.calWheelDelta += event.angleDelta.y
                            if (Math.abs(root.calWheelDelta) < 120) return
                            root.applyMonth(root.calWheelDelta > 0 ? -1 : 1)
                            root.calWheelDelta = 0
                        }
                    }

                    MonthGrid {
                        id: calDays
                        width: parent.width
                        month: root.calMonth
                        year: root.calYear
                        locale: root.weekLocale
                        spacing: 0
                        padding: 0

                        delegate: Item {
                            id: cell
                            required property var model

                            implicitWidth: 38
                            implicitHeight: 31
                            opacity: cell.model.month === root.calMonth ? 1.0 : 0.35

                            Rectangle {
                                anchors.centerIn: parent
                                width: 26
                                height: 26
                                radius: 13
                                visible: cell.model.today
                                color: "#ff3b30"
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                width: 26
                                height: 26
                                radius: 13
                                visible: !cell.model.today && (cell.model.month === root.calMonth) && cellMouse.containsMouse
                                color: Qt.alpha("#ffffff", 0.10)
                            }

                            StyledText {
                                anchors.centerIn: parent
                                text: cell.model.day
                                font.family: "Noto Sans, Cantarell, sans-serif"
                                font.pixelSize: 12
                                font.weight: cell.model.today ? Font.Bold : Font.Medium
                                color: cell.model.today ? "#ffffff" : "#f5f5f7"
                            }

                            MouseArea {
                                id: cellMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                            }
                        }
                    }
                }
            }
        }
    }
}
