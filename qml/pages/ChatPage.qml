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

    property bool searchMode: false
    property bool searching: false
    property bool searchAttempted: false
    property string searchError: ""
    property string pendingScrollTs: ""

    header: PageHeader {
        id: header
        title: searchMode
               ? i18n.tr("Search")
               : (channelTitle || i18n.tr("Chat"))
        leadingActionBar.actions: [
            Action {
                iconName: "back"
                text: i18n.tr("Back")
                onTriggered: {
                    if (chatPage.searchMode)
                        chatPage.exitSearch()
                    else
                        pageStack.pop()
                }
            }
        ]
        trailingActionBar.actions: [
            Action {
                iconName: "search"
                text: i18n.tr("Search")
                visible: !searchMode
                onTriggered: chatPage.enterSearch()
            },
            Action {
                iconName: "reload"
                text: i18n.tr("Refresh")
                visible: !searchMode
                onTriggered: chatPage.loadHistory(true)
            }
        ]

        extension: Item {
            height: searchMode ? units.gu(6) : 0
            width: header.width > 0 ? header.width : units.gu(40)
            visible: searchMode
            clip: true

            TextField {
                id: searchField
                anchors {
                    fill: parent
                    leftMargin: units.gu(1)
                    rightMargin: units.gu(1)
                    topMargin: units.gu(0.5)
                    bottomMargin: units.gu(1)
                }
                placeholderText: i18n.tr("Search in this conversation…")
                hasClearButton: true
                onTextChanged: searchDebounce.restart()
            }

            Timer {
                id: searchDebounce
                interval: 350
                repeat: false
                onTriggered: chatPage.runSearch(searchField.text)
            }
        }
    }

    ListModel {
        id: messageModel
    }

    ListModel {
        id: searchModel
    }

    function enterSearch() {
        searchMode = true
        activePolling = false
        searchError = ""
        searchAttempted = false
        searchModel.clear()
        errorText = ""
    }

    function exitSearch() {
        searchMode = false
        searching = false
        searchAttempted = false
        searchError = ""
        searchModel.clear()
        activePolling = true
        errorText = ""
        loadHistory(true)
    }

    function runSearch(query) {
        var q = ("" + (query || "")).trim()
        searchError = ""
        if (!q) {
            searchModel.clear()
            searching = false
            searchAttempted = false
            return
        }
        if (!app || !channelId)
            return
        searching = true
        searchAttempted = true
        app.searchInChannel(channelId, q, function(ok, items, message) {
            searching = false
            searchModel.clear()
            if (!ok) {
                searchError = message || i18n.tr("Search failed")
                return
            }
            var list = items || []
            for (var i = 0; i < list.length; i++) {
                var m = list[i]
                searchModel.append({
                    ts: m.ts || "",
                    author: m.author || "",
                    avatarUrl: m.avatarUrl || "",
                    plainText: m.plainText || "",
                    timeLabel: m.timeLabel || "",
                    dayLabel: m.dayLabel || ""
                })
            }
        })
    }

    function openSearchHit(ts) {
        if (!ts || !app)
            return
        searching = true
        searchError = ""
        app.loadMessagesAround(channelId, ts, function(ok, items, message, focusTs) {
            searching = false
            if (!ok) {
                searchError = message || i18n.tr("Couldn't open message")
                return
            }
            searchMode = false
            searchModel.clear()
            activePolling = true
            pendingScrollTs = focusTs || ts
            appendMessages(items || [], true)
            if (newestTs && app.markChannelSeen)
                app.markChannelSeen(channelId, newestTs)
            scrollToTsTimer.start()
        })
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
                avatarUrl: m.avatarUrl || "",
                text: m.text,
                plainText: m.plainText || "",
                imagesJson: m.imagesJson || "[]",
                timeLabel: m.timeLabel,
                isSelf: app && app.userId && m.userId === app.userId,
                replyCount: m.replyCount || 0,
                threadTs: m.threadTs || ""
            })
            if (!newestTs || m.ts > newestTs)
                newestTs = m.ts
        }
        if (!pendingScrollTs && (replace || items.length > 0))
            chatPage.scrollToLatest(replace)
    }

    function openThread(threadTs, rootMessage) {
        if (!threadTs || !channelId)
            return
        pageStack.push(Qt.resolvedUrl("ThreadPage.qml"), {
            app: chatPage.app,
            channelId: chatPage.channelId,
            channelTitle: chatPage.channelTitle,
            threadTs: threadTs,
            rootMessage: rootMessage || null
        })
    }

    function scrollToLatest(forceReliable) {
        if (searchMode || messageModel.count === 0)
            return
        // End index is more reliable than positionViewAtEnd before delegates settle
        listView.positionViewAtIndex(messageModel.count - 1, ListView.End)
        if (forceReliable) {
            scrollToEndTimer.interval = 50
            scrollToEndTimer.start()
            scrollToEndRetry.restart()
        }
    }

    function scrollToPendingTs() {
        var target = pendingScrollTs
        pendingScrollTs = ""
        if (!target)
            return
        for (var i = 0; i < messageModel.count; i++) {
            if (messageModel.get(i).ts === target) {
                listView.positionViewAtIndex(i, ListView.Center)
                return
            }
        }
        chatPage.scrollToLatest(true)
    }

    function loadHistory(fullReload) {
        if (!channelId || searchMode)
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
            chatPage.scrollToLatest(true)
        })
    }

    function pollNew() {
        if (!channelId || !activePolling || sending || searchMode)
            return
        var opts = {}
        if (newestTs)
            opts.oldest = newestTs
        app.loadMessages(channelId, opts, function(ok, items) {
            if (!ok || !items || items.length === 0)
                return
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

    function copyMessageText(value) {
        dismissKeyboard()
        if (!value || !app || !app.copyTextToClipboard)
            return
        if (!app.copyTextToClipboard(value))
            errorText = i18n.tr("Couldn't copy message")
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
        running: chatPage.activePolling && !chatPage.searchMode && chatPage.channelId.length > 0
        onTriggered: chatPage.pollNew()
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

    // Second pass after avatars/images affect delegate heights
    Timer {
        id: scrollToEndRetry
        interval: 250
        repeat: false
        onTriggered: {
            if (messageModel.count > 0 && !chatPage.searchMode)
                listView.positionViewAtIndex(messageModel.count - 1, ListView.End)
        }
    }

    Timer {
        id: scrollToTsTimer
        interval: 80
        repeat: false
        onTriggered: chatPage.scrollToPendingTs()
    }

    function dismissKeyboard() {
        if (composer && composer.visible)
            composer.hideKeyboard()
        // Also drop search-field focus if that keyboard is up
        if (searchMode)
            chatPage.forceActiveFocus()
        Qt.inputMethod.hide()
    }

    Connections {
        target: Qt.inputMethod
        onVisibleChanged: {
            if (Qt.inputMethod.visible && !chatPage.searchMode)
                chatPage.scrollToLatest(false)
        }
    }

    ListView {
        id: listView
        anchors {
            fill: parent
            topMargin: header.height
            bottomMargin: searchMode ? 0 : composer.height
        }
        clip: true
        model: messageModel
        spacing: 0
        visible: !searchMode
        onMovementStarted: chatPage.dismissKeyboard()

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
            replyCount: model.replyCount || 0
            threadTs: model.threadTs || ""
            onImageOpenRequested: chatPage.openImageViewer(imageInfo)
            onImageDownloadRequested: chatPage.downloadImage(imageInfo)
            onImageCopyRequested: chatPage.copyImage(imageInfo)
            onCopyTextRequested: chatPage.copyMessageText(value)
            onThreadOpenRequested: chatPage.openThread(threadTs, {
                ts: model.ts,
                author: model.author,
                avatarUrl: model.avatarUrl || "",
                text: model.text,
                plainText: model.plainText || "",
                imagesJson: model.imagesJson || "[]",
                timeLabel: model.timeLabel,
                isSelf: model.isSelf,
                replyCount: model.replyCount || 0,
                threadTs: model.threadTs || threadTs
            })
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

    // Tap chat area (not the composer) to dismiss the OSK without eating scroll/clicks
    MouseArea {
        anchors.fill: listView
        enabled: listView.visible && Qt.inputMethod.visible
        z: 1
        propagateComposedEvents: true
        onPressed: {
            chatPage.dismissKeyboard()
            mouse.accepted = false
        }
    }

    ListView {
        id: searchList
        anchors {
            fill: parent
            topMargin: header.height
        }
        clip: true
        model: searchModel
        visible: searchMode
        onMovementStarted: chatPage.dismissKeyboard()
        delegate: ListItem {
            height: searchLayout.height + (divider.visible ? divider.height : 0)
            onClicked: chatPage.openSearchHit(model.ts)

            ListItemLayout {
                id: searchLayout
                title.text: model.author
                subtitle.text: model.plainText
                subtitle.maximumLineCount: 2
                summary.text: (model.dayLabel ? model.dayLabel + " · " : "") + model.timeLabel

                UserAvatar {
                    SlotsLayout.position: SlotsLayout.Leading
                    width: units.gu(4)
                    height: units.gu(4)
                    sourceUrl: model.avatarUrl || ""
                    fallbackText: model.author
                }

                ProgressionSlot {}
            }
        }
    }

    MouseArea {
        anchors.fill: searchList
        enabled: searchList.visible && Qt.inputMethod.visible
        z: 1
        propagateComposedEvents: true
        onPressed: {
            chatPage.dismissKeyboard()
            mouse.accepted = false
        }
    }

    ActivityIndicator {
        anchors.centerIn: parent
        running: (loading && messageModel.count === 0 && !searchMode)
                 || (searchMode && searching)
        visible: running
    }

    Label {
        anchors.centerIn: parent
        width: parent.width - units.gu(4)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        visible: searchMode && !searching && searchModel.count === 0 && searchError.length === 0
        color: theme.palette.normal.backgroundSecondaryText
        text: searchAttempted
              ? i18n.tr("No messages found.")
              : i18n.tr("Type to search messages in this conversation.")
    }

    Label {
        anchors.centerIn: parent
        width: parent.width - units.gu(4)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        visible: searchMode && !searching && searchError.length > 0
        color: theme.palette.normal.negative
        text: searchError
    }

    Label {
        anchors {
            left: parent.left
            right: parent.right
            bottom: composer.top
            margins: units.gu(1)
        }
        visible: !searchMode && errorText.length > 0
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
        visible: !searchMode
        sending: chatPage.sending
        mentionProvider: function(query) {
            return chatPage.app ? chatPage.app.searchMentions(query) : []
        }
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
