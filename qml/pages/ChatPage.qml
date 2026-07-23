import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import QtQuick.Dialogs 1.3
import "../components"

Page {
    id: chatPage

    property var app
    property string channelId: ""
    property string channelTitle: ""
    property bool loading: false
    property bool sending: false
    property string errorText: ""
    property string newestTs: ""
    property bool activePolling: true

    header: PageHeader {
        id: header
        title: channelTitle || i18n.tr("Chat")
        trailingActionBar.actions: [
            Action {
                iconName: "reload"
                text: i18n.tr("Refresh")
                onTriggered: chatPage.loadHistory(true)
            }
        ]
    }

    ListModel {
        id: messageModel
    }

    function appendMessages(items, replace) {
        if (replace) {
            messageModel.clear()
            newestTs = ""
        }
        for (var i = 0; i < items.length; i++) {
            var m = items[i]
            if (!replace) {
                var exists = false
                for (var j = 0; j < messageModel.count; j++) {
                    if (messageModel.get(j).ts === m.ts) {
                        exists = true
                        break
                    }
                }
                if (exists)
                    continue
            }
            messageModel.append({
                ts: m.ts,
                userId: m.userId,
                author: m.author,
                text: m.text,
                plainText: m.plainText || "",
                imagesJson: m.imagesJson || "[]",
                timeLabel: m.timeLabel,
                isSelf: app && app.userId && m.userId === app.userId
            })
            if (!newestTs || m.ts > newestTs)
                newestTs = m.ts
        }
        if (replace || items.length > 0)
            scrollToEndTimer.start()
    }

    function loadHistory(fullReload) {
        if (!channelId)
            return
        errorText = ""
        loading = true
        app.loadMessages(channelId, {}, function(ok, items, message) {
            loading = false
            if (!ok) {
                errorText = message || i18n.tr("Failed to load messages")
                return
            }
            appendMessages(items || [], true)
            if (newestTs && app && app.markChannelSeen)
                app.markChannelSeen(channelId, newestTs)
        })
    }

    function pollNew() {
        if (!channelId || !activePolling || sending)
            return
        var opts = {}
        if (newestTs)
            opts.oldest = newestTs
        app.loadMessages(channelId, opts, function(ok, items) {
            if (!ok || !items || items.length === 0)
                return
            // When oldest is set, Slack includes the boundary message; skip known ones
            var fresh = []
            for (var i = 0; i < items.length; i++) {
                if (items[i].ts !== newestTs)
                    fresh.push(items[i])
            }
            if (fresh.length > 0) {
                appendMessages(fresh, false)
                if (newestTs && app && app.markChannelSeen)
                    app.markChannelSeen(channelId, newestTs)
            }
        })
    }

    function basename(url) {
        var s = ("" + (url || "")).split("?")[0]
        var parts = s.split("/")
        var name = parts.length ? parts[parts.length - 1] : "upload"
        try { name = decodeURIComponent(name) } catch (e) {}
        return name || "upload"
    }

    function sendMessage(text) {
        if (composer.hasPendingFile) {
            uploadPending(text)
            return
        }
        sending = true
        errorText = ""
        app.sendMessage(channelId, text, function(ok, message) {
            sending = false
            if (!ok) {
                errorText = message || i18n.tr("Failed to send")
                return
            }
            composer.clear()
            loadHistory(true)
        })
    }

    function uploadPending(caption) {
        var fileUrl = composer.pendingFileUrl
        if (!fileUrl || fileUrl.length === 0)
            return
        sending = true
        errorText = ""
        app.uploadFile(channelId, fileUrl, {
            filename: composer.pendingFileName || basename(fileUrl),
            initialComment: caption || ""
        }, function(ok, message) {
            sending = false
            if (!ok) {
                errorText = message || i18n.tr("Failed to upload")
                return
            }
            composer.clear()
            loadHistory(true)
        })
    }

    function openContentHub() {
        var page = pageStack.push(Qt.resolvedUrl("ContentImportPage.qml"))
        page.imported.connect(function(fileUrl) {
            composer.setPendingFile(fileUrl, basename(fileUrl))
        })
    }

    function openAttachMenu() {
        PopupUtils.open(attachPopover, composer)
    }

    function openImageViewer(info) {
        if (!info)
            return
        pageStack.push(Qt.resolvedUrl("ImageViewerPage.qml"), {
            imageUrl: info.url || "",
            thumbUrl: info.thumb || "",
            mimetype: info.mimetype || "image/jpeg",
            needsAuth: info.needsAuth !== false,
            title: info.name || "",
            loadedSource: info.loadedSource || ""
        })
    }

    function downloadImage(info) {
        if (!info)
            return
        errorText = ""
        imageSaver.saveFromUrls(
            info.url || "",
            info.thumb || "",
            info.needsAuth !== false,
            info.mimetype || "image/jpeg",
            info.name || "slack-image.png",
            function(fileUrl, err) {
                if (!fileUrl) {
                    errorText = err || i18n.tr("Couldn't save image")
                    return
                }
                pageStack.push(Qt.resolvedUrl("ContentExportPage.qml"), { fileUrl: fileUrl })
            }
        )
    }

    function copyImage(info) {
        if (!info || !app || !app.copyImageToClipboard)
            return
        errorText = ""
        app.copyImageToClipboard(info, function(ok, message) {
            if (!ok)
                errorText = message || i18n.tr("Couldn't copy image")
        })
    }

    Component.onCompleted: loadHistory(true)
    Component.onDestruction: activePolling = false

    Timer {
        id: pollTimer
        interval: 8000
        repeat: true
        running: chatPage.activePolling && chatPage.channelId.length > 0
        onTriggered: chatPage.pollNew()
    }

    Timer {
        id: scrollToEndTimer
        interval: 50
        repeat: false
        onTriggered: listView.positionViewAtEnd()
    }

    ListView {
        id: listView
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            bottom: composer.top
        }
        clip: true
        model: messageModel
        spacing: 0

        delegate: MessageDelegate {
            width: listView.width
            author: model.author
            text: model.text
            timeLabel: model.timeLabel
            isSelf: model.isSelf
            imagesJson: model.imagesJson || "[]"
            onImageOpenRequested: chatPage.openImageViewer(imageInfo)
            onImageDownloadRequested: chatPage.downloadImage(imageInfo)
            onImageCopyRequested: chatPage.copyImage(imageInfo)
        }

        Label {
            anchors.centerIn: parent
            width: parent.width - units.gu(4)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            visible: !loading && messageModel.count === 0 && errorText.length === 0
            color: theme.palette.normal.backgroundSecondaryText
            text: i18n.tr("No messages yet. Say hello!")
        }
    }

    ActivityIndicator {
        anchors.centerIn: listView
        running: loading && messageModel.count === 0
        visible: running
    }

    Label {
        anchors {
            left: parent.left
            right: parent.right
            bottom: composer.top
            margins: units.gu(1)
        }
        visible: errorText.length > 0
        wrapMode: Text.Wrap
        color: theme.palette.normal.negative
        fontSize: "small"
        text: errorText
    }

    ImageSaver {
        id: imageSaver
    }

    MessageComposer {
        id: composer
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        sending: chatPage.sending
        onSendRequested: chatPage.sendMessage(message)
        onAttachRequested: chatPage.openAttachMenu()
    }

    Component {
        id: attachPopover
        ActionSelectionPopover {
            actions: ActionList {
                Action {
                    iconName: "image"
                    text: i18n.tr("Photo or video")
                    onTriggered: chatPage.openContentHub()
                }
                Action {
                    iconName: "document-open"
                    text: i18n.tr("Browse files…")
                    onTriggered: fileDialog.open()
                }
            }
        }
    }

    FileDialog {
        id: fileDialog
        title: i18n.tr("Choose a file to upload")
        selectExisting: true
        selectMultiple: false
        nameFilters: [
            i18n.tr("Images (*.png *.jpg *.jpeg *.gif *.webp *.bmp)"),
            i18n.tr("Videos (*.mp4 *.webm *.mov)"),
            i18n.tr("All files (*)")
        ]
        onAccepted: {
            var url = "" + fileDialog.fileUrl
            if (url.length > 0)
                composer.setPendingFile(url, chatPage.basename(url))
        }
    }
}
