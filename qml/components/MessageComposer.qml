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

    readonly property bool hasPendingFile: pendingFileUrl.length > 0
    readonly property bool canSend: !sending && (input.text.trim().length > 0 || hasPendingFile)

    signal sendRequested(string message)
    signal attachRequested()

    function clear() {
        input.text = ""
        clearPendingFile()
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

    Column {
        id: col
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: units.gu(1)
        }
        spacing: units.gu(1)

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
                                 : i18n.tr("Message…")
                enabled: !root.sending
                onAccepted: {
                    if (root.canSend)
                        sendButton.clicked()
                }
            }

            Button {
                id: sendButton
                text: root.sending ? "…" : i18n.tr("Send")
                color: theme.palette.normal.positive
                enabled: root.canSend
                onClicked: {
                    if (!root.canSend)
                        return
                    root.sendRequested(input.text.trim())
                }
            }
        }
    }
}
