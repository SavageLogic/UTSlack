import QtQuick 2.7
import Lomiri.Components 1.3

ListItem {
    id: root
    height: units.gu(5)
    divider.visible: false

    property string titleText: ""
    property int count: 0
    property bool expanded: true
    signal toggled()

    Rectangle {
        anchors.fill: parent
        color: theme.palette.normal.base
        opacity: 0.35
    }

    Row {
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: units.gu(2)
            rightMargin: units.gu(2)
        }
        spacing: units.gu(1)

        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: root.expanded ? "▾" : "▸"
            color: theme.palette.normal.backgroundSecondaryText
            font.bold: true
        }

        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: root.titleText
            font.bold: true
            fontSize: "small"
            color: theme.palette.normal.backgroundText
        }

        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: root.count > 0 ? ("(" + root.count + ")") : ""
            fontSize: "small"
            color: theme.palette.normal.backgroundSecondaryText
        }
    }

    onClicked: root.toggled()
}
