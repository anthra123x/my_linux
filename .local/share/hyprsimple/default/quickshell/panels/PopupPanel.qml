import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs.theme
import qs.components

// Card that grows out of the bar under a bar button, in the bar's own color, joined to it
// by two flared corners. It lives in a transparent window covering everything below the
// bar, so a click anywhere outside the card closes it and the bar stays clickable.
PanelWindow {
    id: panel

    required property var bar
    required property Item anchorItem
    required property string name
    property int panelWidth: Theme.panelWidth
    readonly property bool open: bar.openPanel === name
    default property alias content: box.data

    // 0 closed, 1 open. Overshoots slightly on the way in, and leaves quickly.
    //
    // Opening and closing are two separate animations, started by hand. One animation
    // whose duration and curve were bound to open changed curve while it was already
    // running: a close began on the opening curve, which is nearly finished within a
    // few frames, then switched to the closing curve, which has barely started by
    // then. The panel shut, sprang back open and shut again.
    property real progress: 0

    NumberAnimation {
        id: opening
        target: panel
        property: "progress"
        to: 1
        duration: 280
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.16, 1, 0.3, 1, 1, 1]
    }

    NumberAnimation {
        id: closing
        target: panel
        property: "progress"
        to: 0
        duration: Theme.closeAnim
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.closeCurve
    }

    // Exclusive focus takes the keyboard at once, but while it is held Hyprland sends every
    // pointer event to this window, the bar included. So it is held briefly, then relaxed.
    property bool focusPrimed: false
    property real leftEdge: Theme.panelRadius

    function dismiss() {
        if (open) bar.openPanel = ""
    }

    // True when both lists hold the same objects in the same order. Panels use it to
    // keep a list model stable, so rows are not rebuilt when nothing moved.
    function sameList(a, b) {
        return a.length === b.length && a.every((item, i) => item === b[i])
    }

    // The item that takes the keyboard when the panel opens. The card itself when unset.
    property Item focusTarget: null

    // Center under the anchor button, clamped so the flares stay on screen.
    function place() {
        const center = anchorItem.mapToItem(null, anchorItem.width / 2, 0).x
        const edge = Theme.panelRadius + Theme.gap
        leftEdge = Math.max(edge, Math.min(center - panelWidth / 2, screen.width - panelWidth - edge))
    }

    onPanelWidthChanged: if (open) place()
    onOpenChanged: {
        if (!open) {
            opening.stop()
            closing.start()
            return
        }
        closing.stop()
        opening.start()
        focusPrimed = false
        prime.restart()
        place()
        Qt.callLater(() => (focusTarget ?? card).forceActiveFocus())
    }

    Timer {
        id: prime
        interval: Theme.focusPrime
        onTriggered: panel.focusPrimed = true
    }

    screen: bar.screen
    visible: open || closing.running
    anchors { top: true; bottom: true; left: true; right: true }
    margins.top: Theme.barHeight + 4
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    // No input while closing, so what is underneath can be clicked at once.
    mask: open ? null : noInput
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-panel"
    WlrLayershell.keyboardFocus: !open ? WlrKeyboardFocus.None
        : focusPrimed ? WlrKeyboardFocus.OnDemand
        : WlrKeyboardFocus.Exclusive

    Region { id: noInput }

    // Covers this screen. OtherScreenCatcher, one per bar, covers the others.
    MouseArea {
        anchors.fill: parent
        enabled: panel.open
        acceptedButtons: Qt.AllButtons
        onClicked: panel.dismiss()
    }

    Item {
        id: card

        readonly property real fullHeight: box.implicitHeight + 2 * Theme.lg
        readonly property real flare: 0
        // The corners cannot be rounder than the card is tall while it is still growing.
        readonly property real corner: Math.min(Theme.panelRadius, height / 2)

        x: panel.leftEdge
        width: panel.panelWidth
        height: Math.max(0, fullHeight * panel.progress)
        focus: true
        Keys.onEscapePressed: panel.dismiss()

        // Tarjeta flotante con esquinas completamente redondeadas y borde de vidrio líquido
        Shape {
            x: 0
            width: card.width
            height: card.height
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: 1
                strokeColor: Qt.alpha(Theme.barFg, 0.14)
                fillColor: Qt.alpha(Theme.barBg, 0.90)
                Behavior on fillColor { CAnim {} }

                startX: card.corner
                startY: 0

                PathLine { x: card.width - card.corner; y: 0 }
                PathArc {
                    x: card.width
                    y: card.corner
                    radiusX: card.corner
                    radiusY: card.corner
                    direction: PathArc.Clockwise
                }
                PathLine { x: card.width; y: card.height - card.corner }
                PathArc {
                    x: card.width - card.corner
                    y: card.height
                    radiusX: card.corner
                    radiusY: card.corner
                    direction: PathArc.Clockwise
                }
                PathLine { x: card.corner; y: card.height }
                PathArc {
                    x: 0
                    y: card.height - card.corner
                    radiusX: card.corner
                    radiusY: card.corner
                    direction: PathArc.Clockwise
                }
                PathLine { x: 0; y: card.corner }
                PathArc {
                    x: card.corner
                    y: 0
                    radiusX: card.corner
                    radiusY: card.corner
                    direction: PathArc.Clockwise
                }
            }
        }

        // Clicks inside the card must not reach the dismiss area.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        // The content keeps its full size and is revealed as the card grows.
        Item {
            anchors.fill: parent
            clip: true

            Column {
                id: box
                x: Theme.lg
                y: Theme.lg
                width: parent.width - 2 * Theme.lg
                spacing: Theme.sm
                opacity: Math.max(0, Math.min(1, Math.pow(panel.progress, 1.35)))
            }
        }
    }
}
