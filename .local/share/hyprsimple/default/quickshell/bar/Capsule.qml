import QtQuick
import qs.theme
import qs.components

// A group of bar items on one rounded background.
Rectangle {
    default property alias items: row.data

    implicitWidth: row.width + 2 * Theme.xs
    implicitHeight: Theme.capsule
    radius: Theme.capsuleRadius
    color: Theme.barSurface
    Behavior on color { CAnim {} }

    Row {
        id: row
        anchors.centerIn: parent
    }
}
