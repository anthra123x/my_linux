import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import qs.theme
import qs.components

// One notification card.
// Click runs its default action and closes it; right click or close button dismisses it.
// Styled with polished frosted-glass aesthetics integrated seamlessly inside the bar flare.
Rectangle {
    id: root

    // What to show: { appName, summary, body, picture, critical }.
    required property var record
    // The live notification, null for a card in the history.
    property Notification notification: null
    // Counts replacements of a live notification, which restart its countdown.
    property int stamp: 0
    readonly property bool critical: Boolean(record.critical)
    readonly property int timeout: notification ? Notifications.timeoutFor(notification) : 0
    // 1 when it appears, 0 when its time is up.
    property real remaining: 1
    readonly property string picture: record.picture ? String(record.picture) : ""
    signal dismissed()

    implicitWidth: Theme.notifyWidth
    implicitHeight: contentColumn.implicitHeight + 2 * Theme.md
    radius: 10
    color: hover.containsMouse ? Qt.alpha(Theme.barSurface, 0.75) : Qt.alpha(Theme.barSurface, 0.40)
    border.width: 1
    border.color: critical ? Theme.danger : (hover.containsMouse ? Qt.alpha(Theme.barFg, 0.22) : Qt.alpha(Theme.barFg, 0.08))
    clip: true

    Behavior on color { CAnim {} }
    Behavior on border.color { CAnim {} }

    NumberAnimation on remaining {
        id: countdown
        from: 1
        to: 0
        duration: Math.max(1, root.timeout)
        running: root.timeout > 0
        paused: running && hover.containsMouse
        onFinished: root.notification?.expire()
    }

    onStampChanged: if (timeout > 0) countdown.restart()

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (root.notification && mouse.button === Qt.LeftButton) {
                const action = root.notification.actions.find(a => a.identifier === "default")
                if (action) action.invoke()
            }
            root.notification?.dismiss()
            root.dismissed()
        }
    }

    Column {
        id: contentColumn
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: Theme.md
        }
        spacing: Theme.sm

        // Top Header: App name/source & dismiss button
        Item {
            width: parent.width
            height: 16

            Row {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                spacing: Theme.xs

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.critical ? "warning" : "notifications"
                    color: root.critical ? Theme.danger : Theme.barMuted
                    font.pixelSize: 12
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: (root.record.appName && root.record.appName !== "") ? root.record.appName : "Notificación"
                    color: Theme.barMuted
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
            }

            // Interactive dismiss button
            Item {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: 16
                height: 16
                opacity: closeHover.containsMouse ? 1.0 : (hover.containsMouse ? 0.75 : 0.40)
                Behavior on opacity { CAnim {} }

                Icon {
                    anchors.centerIn: parent
                    text: "close"
                    font.pixelSize: 14
                    color: closeHover.containsMouse ? Theme.danger : Theme.barFg
                    Behavior on color { CAnim {} }
                }

                MouseArea {
                    id: closeHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.notification?.dismiss()
                        root.dismissed()
                    }
                }
            }
        }

        // Body Row: Media frame + message typography
        Row {
            width: parent.width
            spacing: Theme.md

            // Media thumbnail with aspect crop (only shown when a picture is present and valid)
            Item {
                id: mediaContainer
                width: 44
                height: 44
                anchors.top: parent.top
                visible: root.picture !== ""

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: Qt.alpha(Theme.barSurface, 0.70)
                    border.width: 1
                    border.color: Qt.alpha(Theme.barFg, 0.12)
                    clip: true

                    Image {
                        id: mediaImg
                        anchors.fill: parent
                        visible: root.picture !== "" && status === Image.Ready
                        source: root.picture
                        sourceSize: Qt.size(88, 88)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                    }

                    Icon {
                        anchors.centerIn: parent
                        visible: !mediaImg.visible
                        text: root.critical ? "warning" : "notifications"
                        font.pixelSize: 20
                        color: root.critical ? Theme.danger : Theme.barMuted
                    }
                }
            }

            // Text column
            Column {
                width: parent.width - (mediaContainer.visible ? (mediaContainer.width + parent.spacing) : 0)
                anchors.top: parent.top
                spacing: 3

                StyledText {
                    width: parent.width
                    text: root.record.summary ?? ""
                    font.pixelSize: Theme.fontSize
                    font.weight: Font.DemiBold
                    color: Theme.barFg
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                StyledText {
                    width: parent.width
                    visible: (root.record.body ?? "") !== ""
                    text: root.record.body ?? ""
                    textFormat: Text.StyledText
                    font.pixelSize: Theme.fontSizeSmall
                    color: Qt.alpha(Theme.barFg, 0.82)
                    wrapMode: Text.Wrap
                    maximumLineCount: Theme.notifyBodyLines
                    elide: Text.ElideRight
                    onLinkActivated: link => Qt.openUrlExternally(link)
                }

                // Interactive action buttons
                Flow {
                    width: parent.width
                    spacing: Theme.sm
                    topPadding: Theme.xs
                    visible: actions.count > 0

                    Repeater {
                        id: actions
                        model: root.notification?.actions.filter(a => a.identifier !== "default") ?? []

                        Rectangle {
                            required property var modelData
                            implicitWidth: actionLabel.implicitWidth + 16
                            implicitHeight: 24
                            radius: 6
                            color: btnHover.containsMouse ? Qt.alpha(Theme.barFg, 0.18) : Qt.alpha(Theme.barSurface, 0.90)
                            border.width: 1
                            border.color: btnHover.containsMouse ? Qt.alpha(Theme.barFg, 0.28) : Qt.alpha(Theme.barFg, 0.12)
                            Behavior on color { CAnim {} }
                            Behavior on border.color { CAnim {} }

                            StyledText {
                                id: actionLabel
                                anchors.centerIn: parent
                                text: parent.modelData.text
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Medium
                                color: Theme.barFg
                            }

                            MouseArea {
                                id: btnHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    parent.modelData.invoke()
                                    root.notification?.dismiss()
                                    root.dismissed()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Inset countdown progress bar
    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: 8
            rightMargin: 8
            bottomMargin: 6
        }
        height: 2
        radius: 1
        visible: root.timeout > 0 && root.notification !== null
        color: Qt.alpha(Theme.barFg, 0.08)

        Rectangle {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: parent.width * root.remaining
            radius: 1
            color: root.critical ? Theme.danger : Theme.barAccent
        }
    }
}
