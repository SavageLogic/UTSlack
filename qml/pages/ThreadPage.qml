import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import QtQuick.Dialogs 1.3
import "../components"
import "../js/Models.js" as Models

Page {
    id: threadPage

    property var app
    property string channelId: ""
    property string channelTitle: ""
    property string threadTs: ""
    property var rootMessage: null
    property string pendingReactionTs: ""

    property bool loading: false
    property bool sending: false
    property string errorText: ""
    property string newestTs: ""
    property bool activePolling: true

    readonly property string headerSubtitle: {
        var t = channelTitle || ""
        if (t.length === 0)
            return i18n.tr("Thread")
        return t
    }

    header: PageHeader {
        id: header
        title: i18n.tr("Thread")
        subtitle: threadPage.headerSubtitle
        leadingActionBar.actions: [
            Action {
                iconName: "back"
                text: i18n.tr("Back")
                onTriggered: pageStack.pop()
            }
        ]
        trailingActionBar.actions: [
            Action {
                iconName: "reload"
                text: i18n.tr("Refresh")
                onTriggered: threadPage.loadHistory(true)
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
        var added = 0
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
                avatarUrl: m.avatarUrl || "",
                text: m.text,
                plainText: m.plainText || "",
                imagesJson: m.imagesJson || "[]",
                reactionsJson: m.reactionsJson || "[]",
                timeLabel: m.timeLabel,
                isSelf: app && app.userId && m.userId === app.userId,
                replyCount: m.replyCount || 0,
                threadTs: m.threadTs || ""
            })
            added++
            if (!newestTs || m.ts > newestTs)
                newestTs = m.ts
        }
        // Only auto-scroll on full reload or when new messages were actually added
        if (replace || added > 0)
            threadPage.scrollToLatest(replace)
    }

    function scrollToLatest(forceReliable) {
        if (messageModel.count === 0)
            return
        listView.positionViewAtIndex(messageModel.count - 1, ListView.End)
        if (forceReliable) {
            scrollToEndTimer.interval = 50
            scrollToEndTimer.start()
            scrollToEndRetry.restart()
        }
    }

    function loadHistory(fullReload) {
        if (!channelId || !threadTs || !app)
            return
        errorText = ""
        loading = true
        app.loadThread(channelId, threadTs, {}, function(ok, items, message) {
            loading = false
            if (!ok) {
                errorText = message || i18n.tr("Failed to load thread")
                return
            }
            appendMessages(items || [], true)
            if (newestTs && app.markChannelSeen)
                app.markChannelSeen(channelId, newestTs)
        })
    }

    function pollNew() {
        if (!channelId || !threadTs || !activePolling || sending || !app)
            return
        var opts = {}
        if (newestTs)
            opts.oldest = newestTs
        app.loadThread(channelId, threadTs, opts, function(ok, items) {
            if (!ok || !items || items.length === 0)
                return
            var fresh = []
            for (var i = 0; i < items.length; i++) {
                if (items[i].ts && items[i].ts > newestTs)
                    fresh.push(items[i])
            }
            if (fresh.length > 0) {
                appendMessages(fresh, false)
                if (newestTs && app.markChannelSeen)
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
        if (composer.isEditing) {
            updateEditedMessage(text)
            return
        }
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
        }, { threadTs: threadTs })
    }

    function beginEditMessage(ts, plainText) {
        if (!ts)
            return
        errorText = ""
        composer.beginEdit(ts, plainText || "")
    }

    function updateEditedMessage(text) {
        var ts = composer.editingTs
        if (!app || !channelId || !ts)
            return
        sending = true
        errorText = ""
        app.updateMessage(channelId, ts, text, function(ok, message) {
            sending = false
            if (!ok) {
                errorText = message || i18n.tr("Couldn't update message")
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
            initialComment: caption || "",
            threadTs: threadTs
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

    function copyMessageText(value) {
        dismissKeyboard()
        if (!value || !app || !app.copyTextToClipboard)
            return
        if (!app.copyTextToClipboard(value))
            errorText = i18n.tr("Couldn't copy message")
    }

    function deleteMessage(ts) {
        if (!app || !channelId || !ts)
            return
        errorText = ""
        app.deleteMessage(channelId, ts, function(ok, message) {
            if (!ok) {
                errorText = message || i18n.tr("Couldn't delete message")
                return
            }
            var idx = findMessageIndex(ts)
            if (idx >= 0)
                messageModel.remove(idx)
        })
    }

    function findMessageIndex(ts) {
        for (var i = 0; i < messageModel.count; i++) {
            if (messageModel.get(i).ts === ts)
                return i
        }
        return -1
    }

    function updateReactionsOptimistic(ts, name, add) {
        var idx = findMessageIndex(ts)
        if (idx < 0)
            return
        var list = []
        try {
            list = JSON.parse(messageModel.get(idx).reactionsJson || "[]") || []
        } catch (e) {
            list = []
        }
        list = Models.applyReactionOptimistic(list, name, add)
        messageModel.setProperty(idx, "reactionsJson", JSON.stringify(list))
    }

    function handleReactionToggle(ts, name, currentlyMine) {
        if (!app || !channelId || !ts || !name)
            return
        updateReactionsOptimistic(ts, name, !currentlyMine)
        app.toggleReaction(channelId, ts, name, currentlyMine, function(ok, message) {
            if (!ok) {
                updateReactionsOptimistic(ts, name, currentlyMine)
                errorText = message || i18n.tr("Couldn't update reaction")
            }
        })
    }

    function openReactionPicker(ts) {
        if (!ts)
            return
        pendingReactionTs = ts
        if (app && app.loadCustomEmoji)
            app.loadCustomEmoji(function() {})
        PopupUtils.open(reactionPickerComponent, threadPage)
    }

    function applyPickedReaction(name) {
        var ts = pendingReactionTs
        pendingReactionTs = ""
        if (!ts || !name || !app || !channelId)
            return
        var idx = findMessageIndex(ts)
        var alreadyMine = false
        if (idx >= 0) {
            try {
                var list = JSON.parse(messageModel.get(idx).reactionsJson || "[]") || []
                for (var i = 0; i < list.length; i++) {
                    if (list[i].name === name && list[i].me) {
                        alreadyMine = true
                        break
                    }
                }
            } catch (e) {}
        }
        if (alreadyMine)
            return
        updateReactionsOptimistic(ts, name, true)
        app.addReaction(channelId, ts, name, function(ok, message) {
            if (!ok) {
                updateReactionsOptimistic(ts, name, false)
                errorText = message || i18n.tr("Couldn't add reaction")
            }
        })
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

    function dismissKeyboard() {
        if (composer && composer.visible)
            composer.hideKeyboard()
        threadPage.forceActiveFocus()
        Qt.inputMethod.hide()
    }

    Component.onCompleted: loadHistory(true)
    Component.onDestruction: activePolling = false

    Timer {
        id: pollTimer
        interval: 8000
        repeat: true
        running: threadPage.activePolling && threadPage.channelId.length > 0
                 && threadPage.threadTs.length > 0
        onTriggered: threadPage.pollNew()
    }

    Timer {
        id: scrollToEndTimer
        interval: 50
        repeat: false
        onTriggered: {
            if (messageModel.count > 0)
                listView.positionViewAtIndex(messageModel.count - 1, ListView.End)
        }
    }

    Timer {
        id: scrollToEndRetry
        interval: 250
        repeat: false
        onTriggered: {
            if (messageModel.count > 0)
                listView.positionViewAtIndex(messageModel.count - 1, ListView.End)
        }
    }

    Connections {
        target: Qt.inputMethod
        onVisibleChanged: {
            if (Qt.inputMethod.visible)
                threadPage.scrollToLatest(false)
        }
    }

    Connections {
        target: composer
        onHeightChanged: {
            if (Qt.inputMethod.visible)
                threadPage.scrollToLatest(false)
        }
    }

    ListView {
        id: listView
        anchors {
            fill: parent
            topMargin: header.height
            bottomMargin: composer.height
        }
        clip: true
        model: messageModel
        spacing: 0
        onMovementStarted: threadPage.dismissKeyboard()

        delegate: MessageDelegate {
            width: listView.width
            ts: model.ts || ""
            author: model.author
            avatarUrl: model.avatarUrl || ""
            text: model.text
            plainText: model.plainText || ""
            timeLabel: model.timeLabel
            isSelf: model.isSelf
            imagesJson: model.imagesJson || "[]"
            reactionsJson: model.reactionsJson || "[]"
            replyCount: 0
            threadTs: model.threadTs || ""
            showThreadActions: false
            onImageOpenRequested: threadPage.openImageViewer(imageInfo)
            onImageDownloadRequested: threadPage.downloadImage(imageInfo)
            onImageCopyRequested: threadPage.copyImage(imageInfo)
            onCopyTextRequested: threadPage.copyMessageText(value)
            onDeleteRequested: threadPage.deleteMessage(ts)
            onEditRequested: threadPage.beginEditMessage(ts, plainText)
            onReactionToggled: threadPage.handleReactionToggle(ts, name, currentlyMine)
            onAddReactionRequested: threadPage.openReactionPicker(ts)
        }

        Label {
            anchors.centerIn: parent
            width: parent.width - units.gu(4)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            visible: !loading && messageModel.count === 0 && errorText.length === 0
            color: theme.palette.normal.backgroundSecondaryText
            text: i18n.tr("No replies yet. Be the first to reply.")
        }
    }

    MouseArea {
        anchors.fill: listView
        enabled: listView.visible && Qt.inputMethod.visible
        z: 1
        propagateComposedEvents: true
        onPressed: {
            threadPage.dismissKeyboard()
            mouse.accepted = false
        }
    }

    ActivityIndicator {
        anchors.centerIn: parent
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
        sending: threadPage.sending
        mentionProvider: function(query) {
            return threadPage.app ? threadPage.app.searchMentions(query) : []
        }
        onSendRequested: threadPage.sendMessage(message)
        onAttachRequested: threadPage.openAttachMenu()
    }

    Component {
        id: reactionPickerComponent
        ReactionPicker {
            app: threadPage.app
            onPicked: threadPage.applyPickedReaction(name)
        }
    }

    Component {
        id: attachPopover
        ActionSelectionPopover {
            actions: ActionList {
                Action {
                    iconName: "image"
                    text: i18n.tr("Photo or video")
                    onTriggered: threadPage.openContentHub()
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
                composer.setPendingFile(url, threadPage.basename(url))
        }
    }
}
