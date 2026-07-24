import QtQuick 2.7
import Lomiri.Components 1.3

Rectangle {
    id: root
    // Grow upward from the page bottom so expansion stays above the OSK.
    height: col.height + units.gu(2)
    color: theme.palette.normal.background
    border.color: theme.palette.normal.base
    border.width: units.dp(1)

    property alias text: input.text
    property bool sending: false
    property string pendingFileUrl: ""
    property string pendingFileName: ""
    property url pendingPreview: ""
    property var mentionProvider: null
    property string editingTs: ""

    readonly property bool hasPendingFile: pendingFileUrl.length > 0
    readonly property bool isEditing: editingTs.length > 0
    // Include in-progress OSK composition — predictive text often withholds
    // letters from `text` until space/punctuation commits them.
    readonly property bool hasTypedText: (input.text && input.text.trim().length > 0)
                                         || input.inputMethodComposing
    readonly property bool canSend: !sending && (hasTypedText || (!isEditing && hasPendingFile))
    readonly property bool mentionOpen: mentionModel.count > 0

    signal sendRequested(string message)
    signal attachRequested()
    signal editCancelled()

    ListModel {
        id: mentionModel
    }

    function clear() {
        input.text = ""
        editingTs = ""
        clearPendingFile()
        mentionModel.clear()
    }

    function clearPendingFile() {
        pendingFileUrl = ""
        pendingFileName = ""
        pendingPreview = ""
    }

    function setPendingFile(fileUrl, fileName) {
        if (root.isEditing)
            root.cancelEdit()
        pendingFileUrl = fileUrl || ""
        pendingFileName = fileName || ""
        var lower = (fileName || fileUrl || "").toLowerCase()
        if (/\.(png|jpe?g|gif|webp|bmp)(\?|$)/.test(lower))
            pendingPreview = fileUrl
        else
            pendingPreview = ""
    }

    function beginEdit(ts, messageText) {
        if (!ts)
            return
        clearPendingFile()
        mentionModel.clear()
        editingTs = ts
        input.text = messageText || ""
        focusInput()
    }

    function cancelEdit() {
        if (!root.isEditing)
            return
        editingTs = ""
        input.text = ""
        mentionModel.clear()
        root.editCancelled()
    }

    function focusInput() {
        input.forceActiveFocus()
    }

    function hideKeyboard() {
        mentionModel.clear()
        input.focus = false
        Qt.inputMethod.hide()
    }

    function submit() {
        if (!root.canSend)
            return
        // Flush any unfinished OSK composition into the field before reading text.
        if (Qt.inputMethod && Qt.inputMethod.commit)
            Qt.inputMethod.commit()
        mentionModel.clear()
        var msg = ("" + input.text).trim()
        if (msg.length === 0 && !( !root.isEditing && root.hasPendingFile))
            return
        root.sendRequested(msg)
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
            height: visible ? units.gu(6) : 0

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

        // Manual row so TextArea autoSize height propagates to the composer
        // (RowLayout often keeps a one-line height and the area overflows under the OSK).
        Item {
            id: row
            width: parent.width
            height: Math.max(units.gu(4), input.height)

            AbstractButton {
                id: attachButton
                anchors {
                    left: parent.left
                    bottom: parent.bottom
                }
                width: units.gu(4)
                height: units.gu(4)
                visible: !root.isEditing
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

            AbstractButton {
                id: cancelEditButton
                anchors {
                    left: parent.left
                    bottom: parent.bottom
                }
                width: units.gu(4)
                height: units.gu(4)
                visible: root.isEditing
                enabled: !root.sending
                onClicked: root.cancelEdit()

                Icon {
                    anchors.centerIn: parent
                    width: units.gu(3)
                    height: units.gu(3)
                    name: "close"
                    color: theme.palette.normal.backgroundText
                }
            }

            AbstractButton {
                id: sendButton
                anchors {
                    right: parent.right
                    bottom: parent.bottom
                }
                width: units.gu(4)
                height: units.gu(4)
                enabled: root.canSend
                opacity: enabled ? 1.0 : 0.45
                onClicked: root.submit()

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    // Ubuntu orange
                    color: "#E95420"
                }

                Icon {
                    anchors.centerIn: parent
                    width: units.gu(2.2)
                    height: units.gu(2.2)
                    name: "send"
                    color: "#FFFFFF"
                }
            }

            TextArea {
                id: input
                anchors {
                    left: parent.left
                    right: sendButton.left
                    bottom: parent.bottom
                    leftMargin: units.gu(5)
                    rightMargin: units.gu(1)
                }
                // Height comes from autoSize — do not bind height to parent
                // or the composer cannot grow upward above the keyboard.
                autoSize: true
                maximumLineCount: 6
                wrapMode: TextEdit.Wrap
                textFormat: TextEdit.PlainText
                // Commit each key into `text` immediately so send enables on
                // the first character (predictive text otherwise buffers letters).
                inputMethodHints: Qt.ImhNoPredictiveText
                placeholderText: root.isEditing
                                 ? i18n.tr("Edit message…")
                                 : (root.hasPendingFile
                                    ? i18n.tr("Add a caption…")
                                    : i18n.tr("Message… @ to mention"))
                enabled: !root.sending
                onTextChanged: root.refreshMentions()
            }
        }
    }
}
