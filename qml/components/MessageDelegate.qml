import QtQuick 2.7
import Lomiri.Components 1.3

Item {
    id: root
    width: parent ? parent.width : units.gu(40)
    height: contentRow.height + units.gu(1)

    property string author: ""
    property string avatarUrl: ""
    property string text: ""
    property string timeLabel: ""
    property bool isSelf: false
    property string imagesJson: "[]"

    property var imageList: []

    onImagesJsonChanged: parseImages()
    Component.onCompleted: parseImages()

    function parseImages() {
        try {
            imageList = JSON.parse(imagesJson || "[]") || []
        } catch (e) {
            imageList = []
        }
    }

    readonly property bool dark: {
        var n = "" + (theme && theme.name ? theme.name : "")
        return n.indexOf("SuruDark") !== -1
    }
    readonly property color bubbleSelf: dark ? "#1B3D2F" : "#E8F5E9"
    readonly property color bubbleSelfBorder: dark ? "#2D6A4F" : "#C8E6C9"
    readonly property color authorColor: dark ? "#C9A0CE" : theme.palette.normal.activity
    readonly property color linkColor: dark ? "#7EB6FF" : theme.palette.normal.activity
    readonly property bool hasText: root.text && root.text.length > 0 && root.text !== "<br/>"
    readonly property bool hasImages: imageList && imageList.length > 0

    signal imageOpenRequested(var imageInfo)
    signal imageDownloadRequested(var imageInfo)
    signal imageCopyRequested(var imageInfo)

    Row {
        id: contentRow
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            topMargin: units.gu(0.5)
            leftMargin: root.isSelf ? units.gu(6) : units.gu(1.5)
            rightMargin: root.isSelf ? units.gu(1.5) : units.gu(6)
        }
        spacing: units.gu(1)

        UserAvatar {
            width: units.gu(4)
            height: units.gu(4)
            visible: !root.isSelf
            sourceUrl: root.avatarUrl
            fallbackText: root.author
            fallbackColor: "#4A154B"
        }

        Column {
            id: bubbleCol
            width: contentRow.width - (root.isSelf ? 0 : (units.gu(4) + contentRow.spacing))
            spacing: units.gu(0.25)

            Label {
                visible: !root.isSelf && root.author.length > 0
                text: root.author
                fontSize: "small"
                font.bold: true
                color: root.authorColor
            }

            Rectangle {
                width: parent.width
                height: innerCol.height + units.gu(1.5)
                radius: units.gu(1)
                color: root.isSelf ? root.bubbleSelf : theme.palette.normal.foreground
                border.color: root.isSelf ? root.bubbleSelfBorder : theme.palette.normal.base
                border.width: units.dp(1)
                visible: root.hasText || root.hasImages

                Column {
                    id: innerCol
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: units.gu(1)
                    }
                    spacing: units.gu(1)

                    Text {
                        width: parent.width
                        visible: root.hasText
                        text: root.hasText ? root.text : ""
                        textFormat: Text.RichText
                        wrapMode: Text.Wrap
                        color: theme.palette.normal.foregroundText
                        linkColor: root.linkColor
                        onLinkActivated: {
                            if (link && link.length > 0)
                                Qt.openUrlExternally(link)
                        }
                    }

                    Repeater {
                        model: root.imageList
                        delegate: SlackImage {
                            width: innerCol.width
                            imageUrl: modelData.url || ""
                            thumbUrl: modelData.thumb || modelData.url || ""
                            mimetype: modelData.mimetype || "image/jpeg"
                            needsAuth: modelData.needsAuth !== false
                            title: modelData.name || ""
                            onOpenRequested: root.imageOpenRequested(imageInfo())
                            onDownloadRequested: root.imageDownloadRequested(imageInfo())
                            onCopyRequested: root.imageCopyRequested(imageInfo())
                        }
                    }
                }
            }

            Label {
                anchors.right: parent.right
                text: root.timeLabel
                fontSize: "x-small"
                color: theme.palette.normal.backgroundTertiaryText
            }
        }
    }
}
