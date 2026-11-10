import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Mpris
import qs.theme
import qs.components

// Isla dinamica central tipo macOS / iOS:
// - Reposo: Presenta la fecha y hora sincronizada (calendario).
// - Reproduciendo: Morfismo animado expansivo con avatar circular, ecualizador visualizador animado,
//   metadatos de la pista y reloj compacto.
// - Interaccion: Clic izquierdo expande la isla dinamica en un reproductor completo tipo iOS;
//   clic sobre el reloj abre el calendario; clic derecho conmuta entre reproductor y calendario.
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

    implicitHeight: Theme.capsule
    implicitWidth: mainRow.implicitWidth + 2 * Theme.md
    radius: height / 2
    color: root.active ? Theme.barSurface : Qt.alpha(Theme.barSurface, 0.95)
    border.width: 1
    border.color: root.active ? root.playerAccent : (root.isPlaying ? Qt.alpha(root.playerAccent, 0.45) : Qt.alpha(Theme.barFg, 0.12))

    // Se desvanece suavemente cuando la isla expandida toma el control
    opacity: bar.openPanel === "media" ? 0.0 : 1.0
    Behavior on opacity { Anim { duration: 180 } }

    Behavior on implicitWidth {
        NumberAnimation {
            duration: 320
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

        // --- MODO REPOSO: Calendario y Reloj ---
        Row {
            id: idleContent
            visible: !root.isPlaying
            spacing: Theme.sm
            anchors.verticalCenter: parent.verticalCenter

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                text: Theme.icon.calendar
                color: Theme.secondary
                fill: root.activeCalendar ? 1 : 0
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(clock.date, "dddd HH:mm")
                font.weight: Font.Medium
                color: Theme.barFg
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
                    color: root.playerAccent
                }

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.alpha(root.playerAccent, 0.45)
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
                font.weight: Font.DemiBold
                color: Theme.barFg
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
                    color: root.playerAccent
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
                    color: root.playerAccent
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
                    color: root.playerAccent
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
                    color: root.playerAccent
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
                color: Theme.barMuted
                font.pixelSize: 10
            }

            // Reloj compacto lateral
            StyledText {
                id: compactClock
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(clock.date, "HH:mm")
                font.weight: Font.Medium
                color: Theme.barMuted
            }
        }
    }

    // Capa de hover interactivo
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: Theme.tint(islandMouse.containsMouse ? Theme.tintHover : 0)
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
            if (root.hasMedia) {
                // Si pulsa sobre el area del reloj compacto (ultimos 48px a la derecha)
                if (mouse.x > root.width - 48) {
                    bar.toggle("calendar")
                } else {
                    // Si pulsa sobre la isla multimedia, se expande la Dynamic Island
                    bar.toggle("media")
                }
            } else {
                // Si no hay musica disponible, abre el calendario
                bar.toggle("calendar")
            }
        }
    }

    Tooltip {
        target: root
        text: root.hasMedia
            ? (root.artist !== "" ? `${root.artist}: ${root.title} (Clic para expandir isla)` : `${root.title} (Clic para expandir isla)`)
            : Qt.formatDate(clock.date, "dddd, d MMMM yyyy")
        hovered: islandMouse.containsMouse && !root.active
    }
}
