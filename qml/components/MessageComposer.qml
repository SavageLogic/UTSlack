import QtQuick 2.7
import Lomiri.Components 1.3
import QtQuick.Layouts 1.3

Rectangle {
    id: root
    height: col.height + units.gu(1.5)
    color: theme.palette.normal.background
    border.color: theme.palette.normal.base
    border.width: units.dp(1)

    property alias text: input.text
    property bool sending: false
    property string pendingFileUrl: ""
    property string pendingFileName: ""
    property url pendingPreview: ""
    property var mentionProvider: null

    readonly property bool hasPendingFile: pendingFileUrl.length > 0
    readonly property bool canSend: !sending && (input.text.trim().length > 0 || hasPendingFile)
    readonly property bool mentionOpen: mentionModel.count > 0

    signal sendRequested(string message)
    signal attachRequested()

    ListModel {
        id: mentionModel
    }

    function clear() {
        input.text = ""
        clearPendingFile()
        mentionModel.clear()
    }

    function clearPendingFile() {
        pendingFileUrl = ""
        pendingFileName = ""
        pendingPreview = ""
    }

    function setPendingFile(fileUrl, fileName) {
        pendingFileUrl = fileUrl || ""
        pendingFileName = fileName || ""
        var lower = (fileName || fileUrl || "").toLowerCase()
        if (/\.(png|jpe?g|gif|webp|bmp)(\?|$)/.test(lower))
            pendingPreview = fileUrl
        else
            pendingPreview = ""
    }

    function focusInput() {
        input.forceActiveFocus()
    }

    function hideKeyboard() {
        mentionModel.clear()
        input.focus = false
        Qt.inputMethod.hide()
    }

    function activeMentionQuery(text) {
        var s = "" + (text || "")
        var match = s.match(/(^|[\s\u00A0])@([^\s@]*)$/)
        if (!match)
            return null
        return match[2]
    }

    function refreshMentions() {
        mentionModel.clear()
        if (!root.mentionProvider || typeof root.mentionProvider !== "function")
            return
        var query = activeMentionQuery(input.text)
        if (query === null)
            return
        // Require at least "@" — show suggestions once user typed @
        var hits = root.mentionProvider(query) || []
        for (var i = 0; i < hits.length; i++) {
            mentionModel.append({
                userId: hits[i].id || "",
                label: hits[i].label || hits[i].name || "",
                userName: hits[i].name || ""
            })
        }
    }

    function applyMention(label) {
        var s = "" + input.text
        var replaced = s.replace(/(^|[\s\u00A0])@([^\s@]*)$/, function(_, pre) {
            return pre + "@" + label + " "
        })
        input.text = replaced
        mentionModel.clear()
        input.forceActiveFocus()
    }

    Column {
        id: col
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: units.gu(1)
        }
        spacing: units.gu(1)

        Rectangle {
            id: mentionBox
            width: parent.width
            height: mentionOpen ? Math.min(mentionList.contentHeight, units.gu(24)) : 0
            visible: mentionOpen
            radius: units.gu(0.5)
            color: theme.palette.normal.foreground
            border.color: theme.palette.normal.base
            border.width: units.dp(1)
            clip: true

            ListView {
                id: mentionList
                anchors.fill: parent
                model: mentionModel
                clip: true
                delegate: ListItem {
                    height: units.gu(5)
                    divider.visible: true
                    onClicked: root.applyMention(model.label)

                    ListItemLayout {
                        title.text: "@" + model.label
                        subtitle.text: model.userName
                        subtitle.visible: model.userName.length > 0 && model.userName !== model.label
                    }
                }
            }
        }

        Row {
            id: pendingRow
            visible: root.hasPendingFile
            width: parent.width
            spacing: units.gu(1)

            Image {
                visible: root.pendingPreview.toString().length > 0
                source: root.pendingPreview
                width: units.gu(6)
                height: units.gu(6)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }

            Label {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - (pendingRow.children[0].visible ? units.gu(7) : 0) - units.gu(5)
                elide: Text.ElideMiddle
                text: root.pendingFileName || root.pendingFileUrl
                color: theme.palette.normal.backgroundSecondaryText
                fontSize: "small"
            }

            AbstractButton {
                anchors.verticalCenter: parent.verticalCenter
                width: units.gu(4)
                height: units.gu(4)
                onClicked: root.clearPendingFile()
                Label {
                    anchors.centerIn: parent
                    text: "✕"
                    color: theme.palette.normal.negative
                }
            }
        }

        RowLayout {
            id: row
            width: parent.width
            spacing: units.gu(1)

            AbstractButton {
                id: attachButton
                Layout.preferredWidth: units.gu(4)
                Layout.preferredHeight: units.gu(4)
                enabled: !root.sending
                onClicked: root.attachRequested()

                Icon {
                    anchors.centerIn: parent
                    width: units.gu(3)
                    height: units.gu(3)
                    name: "attachment"
                    color: theme.palette.normal.backgroundText
                }
            }

            TextField {
                id: input
                Layout.fillWidth: true
                placeholderText: root.hasPendingFile
                                 ? i18n.tr("Add a caption…")
                                 : i18n.tr("Message… @ to mention")
                enabled: !root.sending
                onTextChanged: root.refreshMentions()
                onAccepted: {
                    if (root.mentionOpen && mentionModel.count > 0) {
                        root.applyMention(mentionModel.get(0).label)
                        return
                    }
                    if (!root.canSend)
                        return
                    mentionModel.clear()
                    root.sendRequested(input.text.trim())
                }
            }
        }
    }
}
