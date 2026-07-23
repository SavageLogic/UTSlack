import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import "../js/Models.js" as Models

Item {
    id: root
    width: parent ? parent.width : units.gu(40)
    height: cell.height + units.gu(1.5)

    property string ts: ""
    property string author: ""
    property string avatarUrl: ""
    property string text: ""
    property string plainText: ""
    property string timeLabel: ""
    property bool isSelf: false
    property string imagesJson: "[]"
    property string reactionsJson: "[]"
    property int replyCount: 0
    property string threadTs: ""
    property bool showThreadActions: true

    property var imageList: []
    property var reactionList: []
    property bool childPressed: false
    property bool menuOpen: false

    onImagesJsonChanged: parseImages()
    onReactionsJsonChanged: parseReactions()
    Component.onCompleted: {
        parseImages()
        parseReactions()
    }

    function parseImages() {
        try {
            imageList = JSON.parse(imagesJson || "[]") || []
        } catch (e) {
            imageList = []
        }
    }

    function parseReactions() {
        try {
            reactionList = JSON.parse(reactionsJson || "[]") || []
        } catch (e) {
            reactionList = []
        }
    }

    function reactionGlyph(name) {
        var d = Models.reactionDisplay(name)
        return (d && d.glyph) ? d.glyph : ""
    }

    function reactionUrl(name) {
        var d = Models.reactionDisplay(name)
        return (d && d.url) ? d.url : ""
    }

    function reactionLabel(name) {
        var d = Models.reactionDisplay(name)
        return (d && d.label) ? d.label : (":" + name + ":")
    }

    readonly property bool dark: {
        var n = "" + (theme && theme.name ? theme.name : "")
        return n.indexOf("SuruDark") !== -1
    }
    readonly property color pressHighlight: theme.palette.highlighted.background
    readonly property color authorColor: dark ? "#C9A0CE" : theme.palette.normal.activity
    readonly property color linkColor: dark ? "#7EB6FF" : theme.palette.normal.activity
    readonly property color chipMineBg: dark ? "#3D2A4A" : "#F4E8F5"
    readonly property color chipMineBorder: dark ? "#C9A0CE" : "#4A154B"
    readonly property bool hasText: root.text && root.text.length > 0 && root.text !== "<br/>"
    readonly property bool hasImages: imageList && imageList.length > 0
    readonly property bool hasReactions: reactionList && reactionList.length > 0
    readonly property string effectiveThreadTs: root.threadTs || root.ts
    readonly property string repliesLabel: {
        if (root.replyCount <= 0)
            return ""
        if (root.replyCount === 1)
            return i18n.tr("1 reply")
        return i18n.tr("%1 replies").arg(root.replyCount)
    }
    readonly property string copyPayload: {
        var p = ("" + root.plainText).trim()
        if (p.length > 0)
            return p
        return ("" + root.text)
            .replace(/<br\s*\/?>/gi, "\n")
            .replace(/<[^>]+>/g, "")
            .replace(/&amp;/g, "&")
            .replace(/&lt;/g, "<")
            .replace(/&gt;/g, ">")
            .replace(/&quot;/g, "\"")
            .trim()
    }
    readonly property bool highlighted: pressArea.pressed || root.childPressed || root.menuOpen

    signal imageOpenRequested(var imageInfo)
    signal imageDownloadRequested(var imageInfo)
    signal imageCopyRequested(var imageInfo)
    signal copyTextRequested(string value)
    signal threadOpenRequested(string threadTs)
    signal reactionToggled(string ts, string name, bool currentlyMine)
    signal addReactionRequested(string ts)

    function openCopyMenu(caller) {
        root.menuOpen = true
        root.childPressed = false
        var popup = PopupUtils.open(messageMenu, caller || root)
        if (popup) {
            popup.onVisibleChanged.connect(function() {
                if (popup && !popup.visible)
                    root.menuOpen = false
            })
            popup.onDestruction.connect(function() {
                root.menuOpen = false
            })
        } else {
            root.menuOpen = false
        }
    }

    function openThread() {
        if (!root.showThreadActions)
            return
        var t = root.effectiveThreadTs
        if (!t)
            return
        root.threadOpenRequested(t)
    }

    function beginChildPress() {
        root.childPressed = true
    }

    function endChildPress() {
        root.childPressed = false
    }

    Rectangle {
        anchors.fill: parent
        color: root.highlighted ? root.pressHighlight : "transparent"
    }

    MouseArea {
        id: pressArea
        anchors.fill: parent
        onPressAndHold: root.openCopyMenu(root)
    }

    Row {
        id: cell
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            leftMargin: units.gu(1.5)
            rightMargin: units.gu(1.5)
            topMargin: units.gu(0.75)
        }
        spacing: units.gu(1)

        UserAvatar {
            width: units.gu(4)
            height: units.gu(4)
            sourceUrl: root.avatarUrl
            fallbackText: root.author
            fallbackColor: "#4A154B"
        }

        Column {
            id: bodyCol
            width: cell.width - units.gu(4) - cell.spacing
            spacing: units.gu(0.35)

            Item {
                width: parent.width
                height: Math.max(authorLabel.height, timeLabelItem.height)

                Label {
                    id: authorLabel
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                        right: timeLabelItem.left
                        rightMargin: units.gu(1)
                    }
                    text: root.author
                    fontSize: "small"
                    font.bold: true
                    color: root.authorColor
                    elide: Text.ElideRight
                }

                Label {
                    id: timeLabelItem
                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }
                    text: root.timeLabel
                    fontSize: "x-small"
                    color: theme.palette.normal.backgroundTertiaryText
                }
            }

            Text {
                id: msgLabel
                width: parent.width
                visible: root.hasText
                text: root.hasText ? root.text : ""
                textFormat: Text.RichText
                wrapMode: Text.Wrap
                color: theme.palette.normal.backgroundText
                linkColor: root.linkColor

                MouseArea {
                    anchors.fill: parent
                    enabled: root.hasText
                    onPressed: root.beginChildPress()
                    onReleased: root.endChildPress()
                    onCanceled: root.endChildPress()
                    onClicked: {
                        var link = ""
                        try {
                            link = msgLabel.linkAt(mouse.x, mouse.y) || ""
                        } catch (e) {
                            link = ""
                        }
                        if (link.length > 0)
                            Qt.openUrlExternally(link)
                    }
                    onPressAndHold: root.openCopyMenu(root)
                }
            }

            Repeater {
                model: root.imageList
                delegate: SlackImage {
                    width: bodyCol.width
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

            Flow {
                id: reactionFlow
                width: parent.width
                spacing: units.gu(0.5)
                visible: root.hasReactions

                Repeater {
                    model: root.reactionList
                    delegate: AbstractButton {
                        id: chipBtn
                        width: chipRow.width + units.gu(1.2)
                        height: units.gu(3.2)
                        onPressedChanged: {
                            if (pressed)
                                root.beginChildPress()
                            else
                                root.endChildPress()
                        }
                        onClicked: root.reactionToggled(root.ts, modelData.name, !!modelData.me)

                        Rectangle {
                            anchors.fill: parent
                            radius: units.gu(1.5)
                            color: modelData.me ? root.chipMineBg : theme.palette.normal.foreground
                            border.width: units.dp(1)
                            border.color: modelData.me
                                         ? root.chipMineBorder
                                         : theme.palette.normal.base
                        }

                        Row {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: units.gu(0.4)

                            Image {
                                visible: root.reactionUrl(modelData.name).length > 0
                                source: root.reactionUrl(modelData.name)
                                width: units.gu(2)
                                height: units.gu(2)
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                            }

                            Label {
                                visible: root.reactionUrl(modelData.name).length === 0
                                text: root.reactionLabel(modelData.name)
                                fontSize: "small"
                                color: theme.palette.normal.backgroundText
                            }

                            Label {
                                text: "" + (modelData.count || 1)
                                fontSize: "x-small"
                                color: theme.palette.normal.backgroundSecondaryText
                            }
                        }
                    }
                }
            }

            AbstractButton {
                id: repliesButton
                visible: root.showThreadActions && root.replyCount > 0
                height: visible ? units.gu(3) : 0
                width: parent.width
                onPressedChanged: {
                    if (pressed)
                        root.beginChildPress()
                    else
                        root.endChildPress()
                }
                onClicked: root.openThread()

                Label {
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                    }
                    text: root.repliesLabel
                    fontSize: "small"
                    font.bold: true
                    color: theme.palette.normal.activity
                }
            }
        }
    }

    Component {
        id: messageMenu
        ActionSelectionPopover {
            actions: ActionList {
                Action {
                    iconName: "add"
                    text: i18n.tr("Add reaction")
                    enabled: root.ts.length > 0
                    onTriggered: root.addReactionRequested(root.ts)
                }
                Action {
                    iconName: "mail-reply"
                    text: i18n.tr("Reply in thread")
                    visible: root.showThreadActions
                    enabled: root.effectiveThreadTs.length > 0
                    onTriggered: root.openThread()
                }
                Action {
                    iconName: "edit-copy"
                    text: i18n.tr("Copy message")
                    enabled: root.copyPayload.length > 0
                    onTriggered: root.copyTextRequested(root.copyPayload)
                }
            }
        }
    }
}
