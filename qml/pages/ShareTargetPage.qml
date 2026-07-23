import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Content 1.3
import "../components"

Page {
    id: sharePage

    property var app
    property var transfer: null
    property var payload: null // { kind: "link"|"file", url, text, name }

    property bool loading: false
    property bool sending: false
    property string errorText: ""
    property var allItems: []

    header: PageHeader {
        id: header
        title: i18n.tr("Share to Slack")
        leadingActionBar.actions: [
            Action {
                iconName: "close"
                text: i18n.tr("Cancel")
                enabled: !sharePage.sending
                onTriggered: sharePage.cancelShare()
            }
        ]
        extension: Item {
            height: units.gu(6)
            width: header.width > 0 ? header.width : units.gu(40)
            TextField {
                id: searchField
                anchors {
                    fill: parent
                    leftMargin: units.gu(1)
                    rightMargin: units.gu(1)
                    topMargin: units.gu(0.5)
                    bottomMargin: units.gu(1)
                }
                placeholderText: i18n.tr("Search conversations…")
                onTextChanged: sharePage.applyFilter()
            }
        }
    }

    ListModel {
        id: listModel
    }

    readonly property string previewText: {
        if (!payload)
            return ""
        if (payload.kind === "link")
            return payload.url || payload.text || ""
        return payload.name || payload.url || i18n.tr("Attachment")
    }

    function basename(url) {
        var s = ("" + (url || "")).split("?")[0]
        var parts = s.split("/")
        var name = parts.length ? parts[parts.length - 1] : "file"
        try { name = decodeURIComponent(name) } catch (e) {}
        return name || "file"
    }

    function matchesFilter(item, q) {
        if (!q || q.length === 0)
            return true
        return (item.title && item.title.toLowerCase().indexOf(q) !== -1)
            || (item.name && item.name.toLowerCase().indexOf(q) !== -1)
            || (item.subtitle && item.subtitle.toLowerCase().indexOf(q) !== -1)
    }

    function applyFilter() {
        var q = searchField.text.trim().toLowerCase()
        listModel.clear()
        var items = allItems || []
        for (var i = 0; i < items.length; i++) {
            var it = items[i]
            if (!matchesFilter(it, q))
                continue
            listModel.append({
                convId: it.id,
                title: it.title,
                subtitle: it.subtitle,
                isIm: !!(it.isIm || it.isMpim),
                isPrivate: !!it.isPrivate,
                avatarUrl: it.avatarUrl || ""
            })
        }
    }

    function reload() {
        if (!app)
            return
        errorText = ""
        loading = true
        app.loadConversations(function(ok, items, message) {
            loading = false
            if (!ok) {
                errorText = message || i18n.tr("Failed to load conversations")
                allItems = []
                listModel.clear()
                return
            }
            allItems = items || []
            applyFilter()
        })
    }

    function finalizeTransfer() {
        if (!transfer)
            return
        try {
            if (typeof transfer.finalize === "function")
                transfer.finalize()
            else
                transfer.state = ContentTransfer.Collected
        } catch (e) {
            console.log("[share] finalize failed", e)
        }
        transfer = null
    }

    function abortTransfer() {
        if (!transfer)
            return
        try {
            transfer.state = ContentTransfer.Aborted
        } catch (e) {
            console.log("[share] abort failed", e)
        }
        transfer = null
    }

    function cancelShare() {
        abortTransfer()
        if (app && app.clearPendingShare)
            app.clearPendingShare()
        pageStack.pop()
    }

    function sendTo(channelId, title) {
        if (sending || !app || !payload || !channelId)
            return
        sending = true
        errorText = ""

        function done(ok, message) {
            sending = false
            if (!ok) {
                errorText = message || i18n.tr("Couldn't share")
                return
            }
            finalizeTransfer()
            if (app && app.clearPendingShare)
                app.clearPendingShare()
            pageStack.pop()
            pageStack.push(Qt.resolvedUrl("ChatPage.qml"), {
                app: sharePage.app,
                channelId: channelId,
                channelTitle: title || i18n.tr("Chat")
            })
        }

        if (payload.kind === "link") {
            var text = (payload.url || payload.text || "").trim()
            if (!text) {
                done(false, i18n.tr("No link to share"))
                return
            }
            app.sendMessage(channelId, text, done)
            return
        }

        var fileUrl = payload.url || ""
        if (!fileUrl) {
            done(false, i18n.tr("No file to share"))
            return
        }
        app.uploadFile(channelId, fileUrl, {
            filename: payload.name || basename(fileUrl),
            initialComment: (payload.text || "").trim()
        }, done)
    }

    Component.onCompleted: reload()

    Component.onDestruction: {
        if (app)
            app.sharePageOpen = false
    }

    Item {
        anchors {
            fill: parent
            topMargin: header.height
        }

        Column {
            id: previewCol
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: units.gu(2)
            }
            spacing: units.gu(1)

            Label {
                width: parent.width
                text: payload && payload.kind === "link"
                      ? i18n.tr("Link")
                      : i18n.tr("File")
                fontSize: "small"
                color: theme.palette.normal.backgroundSecondaryText
            }

            Label {
                width: parent.width
                text: sharePage.previewText
                wrapMode: Text.WrapAnywhere
                maximumLineCount: 4
                elide: Text.ElideRight
                color: theme.palette.normal.backgroundText
            }

            Label {
                width: parent.width
                visible: errorText.length > 0
                text: errorText
                wrapMode: Text.Wrap
                color: theme.palette.normal.negative
            }

            Label {
                width: parent.width
                text: i18n.tr("Choose a conversation")
                font.bold: true
            }
        }

        ActivityIndicator {
            anchors.centerIn: parent
            running: loading || sending
            visible: running
        }

        ListView {
            id: listView
            anchors {
                left: parent.left
                right: parent.right
                top: previewCol.bottom
                bottom: parent.bottom
                topMargin: units.gu(1)
            }
            clip: true
            model: listModel
            visible: !loading && listModel.count > 0

            delegate: ListItem {
                height: layout.height + (divider.visible ? divider.height : 0)
                enabled: !sharePage.sending
                onClicked: sharePage.sendTo(model.convId, model.title)

                ListItemLayout {
                    id: layout
                    title.text: model.title
                    subtitle.text: model.subtitle

                    Item {
                        SlotsLayout.position: SlotsLayout.Leading
                        width: units.gu(4)
                        height: units.gu(4)

                        UserAvatar {
                            anchors.fill: parent
                            visible: model.isIm && (model.avatarUrl || "").length > 0
                            sourceUrl: model.avatarUrl || ""
                            fallbackText: model.title
                        }

                        Rectangle {
                            anchors.fill: parent
                            visible: !(model.isIm && (model.avatarUrl || "").length > 0)
                            radius: units.gu(0.5)
                            color: model.isIm ? "#36C5F0" : "#4A154B"

                            Label {
                                anchors.centerIn: parent
                                visible: !model.isIm && !model.isPrivate
                                text: "#"
                                color: "#FFFFFF"
                                font.bold: true
                            }

                            Icon {
                                anchors.centerIn: parent
                                visible: !model.isIm && model.isPrivate
                                width: units.gu(2.2)
                                height: units.gu(2.2)
                                name: "lock"
                                color: "#FFFFFF"
                            }

                            Icon {
                                anchors.centerIn: parent
                                visible: model.isIm
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
        }

        Label {
            anchors.centerIn: parent
            width: parent.width - units.gu(4)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            visible: !loading && !sending && errorText.length === 0 && listModel.count === 0
            color: theme.palette.normal.backgroundSecondaryText
            text: i18n.tr("No conversations found.")
        }
    }
}
