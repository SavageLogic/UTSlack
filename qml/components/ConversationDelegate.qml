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

    readonly property bool dark: {
        var n = "" + (theme && theme.name ? theme.name : "")
        return n.indexOf("SuruDark") !== -1
    }
    readonly property bool showAvatar: root.isIm && root.avatarUrl.length > 0

    ListItemLayout {
        id: layout
        title.text: root.titleText
        subtitle.text: root.subtitleText

        Item {
            SlotsLayout.position: SlotsLayout.Leading
            width: units.gu(4)
            height: units.gu(4)

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

        ProgressionSlot {}
    }
}
