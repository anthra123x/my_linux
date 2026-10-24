import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Item {
    id: root
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.QsWindow.window?.screen)
    readonly property Toplevel activeWindow: ToplevelManager.activeToplevel

    property string activeWindowAddress: `0x${activeWindow?.HyprlandToplevel?.address}`
    property bool focusingThisMonitor: HyprlandData.activeWorkspace?.monitor == monitor?.name
    property var biggestWindow: HyprlandData.biggestWindowForWorkspace(HyprlandData.monitors[root.monitor?.id]?.activeWorkspace.id)

    // Ventana que se esta mostrando en esta pantalla: la activa si esta
    // enfocada en este monitor, si no la mayor de su workspace.
    readonly property var shownWindow:
        (root.focusingThisMonitor && root.activeWindow?.activated && root.biggestWindow)
            ? root.activeWindow
            : (root.biggestWindow ?? root.activeWindow)

    // Nombre del icono de esa ventana. AppSearch.guessIcon es el mismo
    // resolutor que usa el dock y el launcher: busca el .desktop del appId y
    // devuelve el nombre de su icono, que Kirigami resuelve contra el tema.
    readonly property string windowIcon: AppSearch.guessIcon(shownWindow?.appId ?? "")

    implicitWidth: row.implicitWidth

    RowLayout {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 6

        AppIcon {
            Layout.alignment: Qt.AlignVCenter
            visible: root.windowIcon.length > 0 && root.windowIcon !== "image-missing"
            implicitSize: 18
            source: root.windowIcon
            color: Appearance.colors.colOnLayer0
        }

        ColumnLayout {
            id: colLayout

            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true
            spacing: -4

            StyledText {
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
                text: root.focusingThisMonitor && root.activeWindow?.activated && root.biggestWindow ?
                    root.activeWindow?.appId :
                    (root.biggestWindow?.class) ?? Translation.tr("Desktop")
            }

            StyledText {
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer0
                elide: Text.ElideRight
                text: root.focusingThisMonitor && root.activeWindow?.activated && root.biggestWindow ?
                    root.activeWindow?.title :
                    (root.biggestWindow?.title) ?? `${Translation.tr("Workspace")} ${monitor?.activeWorkspace?.id ?? 1}`
            }

        }
    }

}
