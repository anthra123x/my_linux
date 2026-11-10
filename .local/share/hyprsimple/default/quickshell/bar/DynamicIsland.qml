import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import qs.theme
import qs.components

// Isla dinamica central tipo macOS:
// - Reposo: Presenta la fecha y hora sincronizada (calendario).
// - Reproduciendo: Morfismo animado expansivo con caratula, ecualizador visualizador animado,
//   metadatos de la pista y reloj compacto.
// - Interaccion: Clic izquierdo despliega el panel multimedia extendido o calendario;
//   clic derecho alterna entre reproductor y calendario.
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

    implicitHeight: Theme.capsule
    implicitWidth: mainRow.implicitWidth + 2 * Theme.md
    radius: height / 2
    color: root.active ? Theme.barSurface : Qt.alpha(Theme.barSurface, 0.95)
    border.width: 1
    border.color: root.active ? Theme.accent : (root.isPlaying ? Qt.alpha(Theme.accent, 0.40) : Qt.alpha(Theme.barFg, 0.12))

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

            // Caratula miniatura o icono de notas musicales
            Rectangle {
                width: 16
                height: 16
                radius: 4
                color: Qt.alpha(Theme.accent, 0.20)
                border.width: 1
                border.color: Qt.alpha(Theme.accent, 0.40)
                clip: true
                anchors.verticalCenter: parent.verticalCenter

                Image {
                    id: miniCover
                    anchors.fill: parent
                    source: root.artUrl
                    fillMode: Image.PreserveAspectCrop
                    visible: status === Image.Ready && root.hasArt
                    asynchronous: true
                }

                Icon {
                    anchors.centerIn: parent
                    visible: !miniCover.visible
                    text: "music_note"
                    font.pixelSize: 13
                    color: Theme.accent
                }
            }

            // Ecualizador animado (barras reactivas tipo Dynamic Island)
            Row {
                id: visualizer
                spacing: 2
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    width: 2.5
                    height: 5
                    radius: 1.25
                    color: Theme.accent
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
                    color: Theme.accent
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
                    color: Theme.accent
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
                    color: Theme.accent
                    anchors.bottom: parent.bottom
                    SequentialAnimation on height {
                        running: root.isPlaying
                        loops: Animation.Infinite
                        NumberAnimation { to: 11; duration: 350; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 3; duration: 310; easing.type: Easing.InOutSine }
                    }
                }
            }

            // Metadatos de reproduccion
            StyledText {
                id: trackLabel
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    if (!root.title) return "Reproduciendo"
                    const full = root.artist !== "" ? `${root.artist} - ${root.title}` : root.title
                    return full.length > 26 ? full.slice(0, 25) + "…" : full
                }
                font.weight: Font.DemiBold
                color: Theme.barFg
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
                    bar.openPanel = root.isPlaying ? "calendar" : "media"
                }
                return
            }

            // Clic izquierdo:
            if (root.isPlaying) {
                // Si pulsa especificamente sobre el area del reloj compacto (ultimos 50px a la derecha)
                if (mouse.x > root.width - 50) {
                    bar.toggle("calendar")
                } else {
                    // Si pulsa sobre la isla multimedia, se extiende el reproductor
                    bar.toggle("media")
                }
            } else {
                // Si no hay musica reproduciendose, abre el calendario
                bar.toggle("calendar")
            }
        }
    }

    Tooltip {
        target: root
        text: root.isPlaying
            ? (root.artist !== "" ? `${root.artist}: ${root.title} (Clic para extender isla)` : `${root.title} (Clic para extender isla)`)
            : Qt.formatDate(clock.date, "dddd, d MMMM yyyy")
        hovered: islandMouse.containsMouse && !root.active
    }
}
