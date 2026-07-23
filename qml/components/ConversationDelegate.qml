import QtQuick 2.7
import Lomiri.Components 1.3

ListItem {
    id: root
    height: layout.height + (divider.visible ? divider.height : 0)

    property string titleText: ""
    property string subtitleText: ""
    property string avatarUrl: ""
    property bool isIm: false
    property bool isPrivate: false
    property bool hasUnread: false
    property bool isHidden: false

    signal hideRequested
    signal unhideRequested
    signal notifyPrefsRequested

    readonly property bool dark: {
        var n = "" + (theme && theme.name ? theme.name : "")
        return n.indexOf("SuruDark") !== -1
    }
    readonly property bool showAvatar: root.isIm && root.avatarUrl.length > 0

    ListItemActions {
        id: hideActions
        actions: [
            Action {
                iconName: "view-off"
                text: i18n.tr("Hide")
                onTriggered: root.hideRequested()
            }
        ]
    }

    ListItemActions {
        id: unhideActions
        actions: [
            Action {
                iconName: "view-on"
                text: i18n.tr("Unhide")
                onTriggered: root.unhideRequested()
            }
        ]
    }

    // LTR swipe → Hide (visible threads). RTL swipe → Unhide (hidden threads).
    leadingActions: root.isHidden ? null : hideActions
    trailingActions: root.isHidden ? unhideActions : null

    onPressAndHold: root.notifyPrefsRequested()

    ListItemLayout {
        id: layout
        title.text: root.titleText
        title.font.bold: root.hasUnread
        title.opacity: root.isHidden ? 0.55 : 1.0
        subtitle.text: root.isHidden
                       ? i18n.tr("Hidden")
                       : root.subtitleText
        subtitle.opacity: root.isHidden ? 0.7 : 1.0

        Item {
            SlotsLayout.position: SlotsLayout.Leading
            width: units.gu(4)
            height: units.gu(4)
            opacity: root.isHidden ? 0.55 : 1.0

            UserAvatar {
                anchors.fill: parent
                visible: root.showAvatar
                sourceUrl: root.avatarUrl
                fallbackText: root.titleText
                fallbackColor: root.dark ? "#5BC8EB" : "#36C5F0"
            }

            Rectangle {
                anchors.fill: parent
                visible: !root.showAvatar
                radius: units.gu(0.5)
                color: root.isIm
                       ? (root.dark ? "#5BC8EB" : "#36C5F0")
                       : "#4A154B"

                Label {
                    anchors.centerIn: parent
                    visible: !root.isIm && !root.isPrivate
                    text: "#"
                    color: "#FFFFFF"
                    font.bold: true
                    fontSize: "medium"
                }

                Icon {
                    anchors.centerIn: parent
                    visible: !root.isIm && root.isPrivate
                    width: units.gu(2.2)
                    height: units.gu(2.2)
                    name: "lock"
                    color: "#FFFFFF"
                }

                Icon {
                    anchors.centerIn: parent
                    visible: root.isIm
                    width: units.gu(2.2)
                    height: units.gu(2.2)
                    name: "message"
                    color: "#FFFFFF"
                }
            }
        }

        Icon {
            SlotsLayout.position: SlotsLayout.Trailing
            name: "view-off"
            width: units.gu(2.2)
            height: units.gu(2.2)
            visible: root.isHidden
            color: theme.palette.normal.backgroundSecondaryText
        }

        ProgressionSlot {
            visible: !root.isHidden
        }
    }
}
