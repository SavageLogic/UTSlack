import QtQuick 2.7
import Lomiri.Components 1.3

Item {
    id: root
    width: units.gu(4)
    height: units.gu(4)

    property string sourceUrl: ""
    property string fallbackText: ""
    property color fallbackColor: "#4A154B"
    property real radius: width / 2

    readonly property bool showPhoto: sourceUrl && sourceUrl.length > 0
            && avatar.status !== Image.Error

    Rectangle {
        id: plate
        anchors.fill: parent
        radius: root.radius
        color: root.fallbackColor
        clip: true

        Label {
            anchors.centerIn: parent
            visible: !root.showPhoto || avatar.status !== Image.Ready
            text: {
                var t = ("" + root.fallbackText).trim()
                if (!t)
                    return "?"
                return t.charAt(0).toUpperCase()
            }
            color: "#FFFFFF"
            font.bold: true
            fontSize: "medium"
        }

        Image {
            id: avatar
            anchors.fill: parent
            visible: root.showPhoto && avatar.status === Image.Ready
            source: root.sourceUrl
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
        }
    }
}
