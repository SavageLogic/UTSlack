import QtQuick 2.7
import Lomiri.Components 1.3

ListItem {
    id: root
    height: layout.height + (divider.visible ? divider.height : 0)

    property string titleText: ""
    property string subtitleText: ""
    property bool isIm: false

    readonly property bool dark: {
        var n = "" + (theme && theme.name ? theme.name : "")
        return n.indexOf("SuruDark") !== -1
    }

    ListItemLayout {
        id: layout
        title.text: root.titleText
        subtitle.text: root.subtitleText

        Rectangle {
            SlotsLayout.position: SlotsLayout.Leading
            width: units.gu(4)
            height: units.gu(4)
            radius: units.gu(0.5)
            color: root.isIm
                   ? (root.dark ? "#5BC8EB" : "#36C5F0")
                   : "#4A154B"

            Label {
                anchors.centerIn: parent
                text: root.isIm ? "DM" : "#"
                color: "#FFFFFF"
                font.bold: true
                fontSize: "small"
            }
        }

        ProgressionSlot {}
    }
}
