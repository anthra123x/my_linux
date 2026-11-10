import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.theme
import qs.components

// Isla dinamica central tipo Apple macOS / iOS:
// - Apariencia de hardware: Capsula de color negro solido (#000000) con trazo sutil de vidrio.
// - Modo reposo: Badge de calendario Apple con fecha y hora digital nitida.
// - Modo reproduccion: Caratula circular con mascara MultiEffect, metadatos sans-serif,
//   ecualizador reactivo animado y reloj compacto.
// - Interaccion: Clic izquierdo despliega la isla dinamica en su reproductor multimedia o en su
//   calendario Apple; clic derecho conmuta fluidamente entre reproductor y calendario.
Rectangle {
    id: root

    required property var bar

    readonly property bool activeCalendar: bar.openPanel === "calendar"
    readonly property bool activeMedia: bar.openPanel === "media"
    readonly property bool active: activeCalendar || activeMedia

    // Estado MPRIS de reproductores
    readonly property var players: Mpris.players.values
    readonly property var activePlayer: {
        if (!players || players.length === 0) return null
        for (let i = 0; i < players.length; i++) {
            if (players[i].playbackState === MprisPlaybackState.Playing) return players[i]
        }
        return players[0]
    }

    readonly property bool isPlaying: activePlayer?.playbackState === MprisPlaybackState.Playing
    readonly property string title: (activePlayer?.trackTitle || "").trim()
    readonly property string artist: (activePlayer?.trackArtist || "").trim()
    readonly property string artUrl: activePlayer?.trackArtUrl || ""
    readonly property bool hasArt: artUrl !== ""
    readonly property bool hasMedia: activePlayer !== null && title !== ""

    // Color adaptativo segun la aplicacion reproductora
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

    // Color ambiental extraido directamente de la caratula de la cancion
    property color coverAccent: playerAccent
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

    implicitHeight: Theme.capsule
    implicitWidth: mainRow.implicitWidth + 2 * Theme.md
    radius: height / 2
    color: "#000000" // Negro azabache solido caracteristico de la Dynamic Island
    border.width: 1
    border.color: root.active ? Qt.alpha("#ffffff", 0.22) : (root.isPlaying ? Qt.alpha(root.coverAccent, 0.45) : Qt.alpha("#ffffff", 0.10))

    // Se desvanece suavemente cuando la isla expandida toma el control
    opacity: root.active ? 0.0 : 1.0
    Behavior on opacity { Anim { duration: 90 } }

    Behavior on implicitWidth {
        NumberAnimation {
            duration: 180
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.16, 1, 0.3, 1, 1, 1]
        }
    }
    Behavior on color { CAnim {} }
    Behavior on border.color { CAnim {} }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Row {
        id: mainRow
        anchors.centerIn: parent
        spacing: Theme.sm

        // --- MODO REPOSO: Badge Apple Calendario + Fecha y Reloj ---
        Row {
            id: idleContent
            visible: !root.isPlaying
            spacing: Theme.sm
            anchors.verticalCenter: parent.verticalCenter

            // Icono de calendario estilo Apple (mini-badge con encabezado rojo y numero de dia)
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

        // --- MODO ACTIVO: Isla Dinamica Multimedia + Reloj ---
        Row {
            id: mediaContent
            visible: root.isPlaying
            spacing: Theme.sm
            anchors.verticalCenter: parent.verticalCenter

            // Avatar circular de caratula (fiel a la referencia iPhone)
            Item {
                width: 18
                height: 18
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    id: miniMask
                    anchors.fill: parent
                    radius: width / 2
                    visible: false
                    layer.enabled: true
                }

                Image {
                    id: miniCover
                    anchors.fill: parent
                    source: root.artUrl
                    fillMode: Image.PreserveAspectCrop
                    visible: status === Image.Ready && root.hasArt
                    asynchronous: true
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: miniMask
                    }
                }

                Icon {
                    anchors.centerIn: parent
                    visible: !miniCover.visible
                    text: "music_note"
                    font.pixelSize: 12
                    color: root.coverAccent
                }

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.alpha(root.coverAccent, 0.45)
                }
            }

            // Metadatos de reproduccion
            StyledText {
                id: trackLabel
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

            // Ecualizador animado (barras reactivas en el extremo derecho de la isla compacta)
            Row {
                id: visualizer
                spacing: 2
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    width: 2.5
                    height: 5
                    radius: 1.25
                    color: root.coverAccent
                    anchors.bottom: parent.bottom
                    SequentialAnimation on height {
                        running: root.isPlaying
                        loops: Animation.Infinite
                        NumberAnimation { to: 12; duration: 320; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 4; duration: 360; easing.type: Easing.InOutSine }
                    }
                }
                Rectangle {
                    width: 2.5
                    height: 9
                    radius: 1.25
                    color: root.coverAccent
                    anchors.bottom: parent.bottom
                    SequentialAnimation on height {
                        running: root.isPlaying
                        loops: Animation.Infinite
                        NumberAnimation { to: 4; duration: 400; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 14; duration: 340; easing.type: Easing.InOutSine }
                    }
                }
                Rectangle {
                    width: 2.5
                    height: 7
                    radius: 1.25
                    color: root.coverAccent
                    anchors.bottom: parent.bottom
                    SequentialAnimation on height {
                        running: root.isPlaying
                        loops: Animation.Infinite
                        NumberAnimation { to: 13; duration: 280; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 5; duration: 420; easing.type: Easing.InOutSine }
                    }
                }
                Rectangle {
                    width: 2.5
                    height: 4
                    radius: 1.25
                    color: root.coverAccent
                    anchors.bottom: parent.bottom
                    SequentialAnimation on height {
                        running: root.isPlaying
                        loops: Animation.Infinite
                        NumberAnimation { to: 11; duration: 350; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 3; duration: 310; easing.type: Easing.InOutSine }
                    }
                }
            }

            // Separador
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: "•"
                color: "#48484a"
                font.pixelSize: 10
            }

            // Reloj compacto lateral
            StyledText {
                id: compactClock
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(clock.date, "HH:mm")
                font.family: "Noto Sans, Cantarell, sans-serif"
                font.pixelSize: 11
                font.weight: Font.Medium
                color: "#98989d"
            }
        }
    }

    // Capa de hover interactivo
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: islandMouse.containsMouse ? Qt.alpha("#ffffff", 0.08) : "transparent"
        Behavior on color { CAnim {} }
    }

    // Gestion de clics e interaccion dinamica
    MouseArea {
        id: islandMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                // Clic derecho conmuta directamente entre media y calendario
                if (bar.openPanel === "media") {
                    bar.openPanel = "calendar"
                } else if (bar.openPanel === "calendar") {
                    bar.openPanel = "media"
                } else {
                    bar.openPanel = root.hasMedia ? "media" : "calendar"
                }
                return
            }

            // Clic izquierdo:
            if (root.hasMedia && root.isPlaying) {
                // Si pulsa sobre el area del reloj compacto (ultimos 48px a la derecha)
                if (mouse.x > root.width - 48) {
                    bar.toggle("calendar")
                } else {
                    // Si pulsa sobre la isla multimedia, se expande la Dynamic Island
                    bar.toggle("media")
                }
            } else {
                // Si no hay musica reproduciendose, abre el calendario en la isla dinamica
                bar.toggle("calendar")
            }
        }
    }

    scale: islandMouse.pressed ? 0.97 : (islandMouse.containsMouse ? 1.02 : 1.0)
    Behavior on scale { Anim { duration: 90 } }

    Tooltip {
        target: root
        text: root.hasMedia
            ? (root.artist !== "" ? `${root.artist}: ${root.title} (Clic para expandir)` : `${root.title} (Clic para expandir)`)
            : Qt.formatDate(clock.date, "dddd, d MMMM yyyy (Clic para expandir)")
        hovered: islandMouse.containsMouse && !root.active
    }
}
