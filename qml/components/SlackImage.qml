import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import Qt.labs.platform 1.0 as Labs
import "../js/SlackClient.js" as Slack
import "../js/Storage.js" as Storage

// Inline Slack image — sized like the official client (capped box), loads a thumb.
Item {
    id: root

    // Match Slack mobile: keep attachments in a modest box, not full bubble width.
    readonly property real maxInlineWidth: Math.min(parent ? parent.width : units.gu(22), units.gu(22))
    readonly property real maxInlineHeight: units.gu(36)

    width: {
        if (root.failed)
            return Math.min(parent ? parent.width : units.gu(22), units.gu(22))
        if (image.status === Image.Ready && image.sourceSize.width > 0 && image.sourceSize.height > 0)
            return fittedWidth
        return Math.min(maxInlineWidth, units.gu(18))
    }
    height: {
        if (root.failed)
            return errorLabel.implicitHeight + units.gu(2)
        if (busy.visible)
            return units.gu(12)
        if (image.status === Image.Ready && image.sourceSize.width > 0 && image.sourceSize.height > 0)
            return fittedHeight
        return units.gu(12)
    }

    readonly property real fittedWidth: {
        var sw = image.sourceSize.width
        var sh = image.sourceSize.height
        if (sw <= 0 || sh <= 0)
            return maxInlineWidth
        var scale = Math.min(maxInlineWidth / sw, maxInlineHeight / sh, 1.0)
        return Math.max(1, Math.ceil(sw * scale))
    }
    readonly property real fittedHeight: {
        var sw = image.sourceSize.width
        var sh = image.sourceSize.height
        if (sw <= 0 || sh <= 0)
            return units.gu(12)
        var scale = Math.min(maxInlineWidth / sw, maxInlineHeight / sh, 1.0)
        return Math.max(1, Math.ceil(sh * scale))
    }

    property string imageUrl: ""
    property string thumbUrl: ""
    property string mimetype: "image/jpeg"
    property bool needsAuth: true
    property string title: ""
    property string fileId: ""

    property string loadedSource: ""
    property bool failed: false
    property int loadSeq: 0
    property string pendingPersistKey: ""
    property string pendingPersistDataUrl: ""

    signal openRequested()
    signal downloadRequested()
    signal copyRequested()

    function cacheDir() {
        try {
            var p = Labs.StandardPaths.writableLocation(Labs.StandardPaths.CacheLocation)
            if (p && ("" + p).length > 0)
                return ("" + p).replace(/\/$/, "")
        } catch (e) {}
        return "/tmp"
    }

    function cacheKeyFor(url, variant) {
        return Storage.mediaCacheKey(root.fileId, url, variant || "thumb")
    }

    function diskPathForKey(key) {
        return cacheDir() + "/media_" + key + ".png"
    }

    function imageInfo() {
        return {
            url: root.imageUrl,
            thumb: root.thumbUrl,
            mimetype: root.mimetype,
            needsAuth: root.needsAuth,
            name: root.title,
            id: root.fileId,
            loadedSource: root.loadedSource
        }
    }

    function tryDiskCache(url, variant) {
        var key = cacheKeyFor(url, variant)
        var entry = Storage.getMediaCacheEntry(key)
        if (!entry || !entry.path)
            return false
        loadedSource = entry.path
        return true
    }

    function persistDataUrl(key, dataUrl) {
        if (!key || !dataUrl || ("" + dataUrl).indexOf("data:") !== 0)
            return
        pendingPersistKey = key
        pendingPersistDataUrl = dataUrl
        persistImage.source = dataUrl
    }

    function startLoad() {
        failed = false
        loadedSource = ""
        loadSeq++
        var seq = loadSeq
        var url = root.thumbUrl || root.imageUrl
        if (!url) {
            failed = true
            return
        }
        if (!root.needsAuth && url.indexOf("http") === 0) {
            if (tryDiskCache(url, "thumb"))
                return
            loadedSource = url
            return
        }
        if (tryDiskCache(url, "thumb"))
            return

        Slack.fetchImageAsDataUrl(url, root.mimetype, function(dataUrl) {
            if (!root || seq !== root.loadSeq)
                return
            if (!dataUrl) {
                if (root.imageUrl && root.imageUrl !== url) {
                    if (tryDiskCache(root.imageUrl, "full"))
                        return
                    Slack.fetchImageAsDataUrl(root.imageUrl, root.mimetype, function(dataUrl2) {
                        if (!root || seq !== root.loadSeq)
                            return
                        if (dataUrl2) {
                            loadedSource = dataUrl2
                            persistDataUrl(cacheKeyFor(root.imageUrl, "full"), dataUrl2)
                        } else {
                            failed = true
                        }
                    })
                } else {
                    failed = true
                }
                return
            }
            loadedSource = dataUrl
            persistDataUrl(cacheKeyFor(url, "thumb"), dataUrl)
        })
    }

    Component.onCompleted: startLoad()
    onImageUrlChanged: startLoad()
    onThumbUrlChanged: startLoad()
    onFileIdChanged: startLoad()

    Image {
        id: persistImage
        width: 1
        height: 1
        visible: false
        asynchronous: true
        cache: false
        onStatusChanged: {
            if (status !== Image.Ready)
                return
            var key = root.pendingPersistKey
            if (!key)
                return
            var path = diskPathForKey(key)
            persistImage.grabToImage(function(result) {
                root.pendingPersistKey = ""
                root.pendingPersistDataUrl = ""
                persistImage.source = ""
                if (!result)
                    return
                var ok = false
                try {
                    ok = result.saveToFile(path)
                } catch (e) {
                    console.log("[media-cache] save failed", e)
                }
                if (!ok)
                    return
                var fileUrl = path.indexOf("file:") === 0 ? path : ("file://" + path)
                Storage.setMediaCacheEntry(key, fileUrl)
            })
        }
    }

    ActivityIndicator {
        id: busy
        anchors.centerIn: parent
        running: !root.failed && root.loadedSource.length === 0 && (root.imageUrl.length > 0 || root.thumbUrl.length > 0)
        visible: running
    }

    Label {
        id: errorLabel
        anchors {
            left: parent.left
            right: parent.right
        }
        visible: root.failed
        wrapMode: Text.Wrap
        fontSize: "small"
        color: theme.palette.normal.backgroundSecondaryText
        text: i18n.tr("Couldn't load image")
                + (root.title ? (": " + root.title) : "")
    }

    Image {
        id: image
        width: root.width
        height: root.height
        visible: root.loadedSource.length > 0 && !root.failed
        source: root.loadedSource
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: true
        onStatusChanged: {
            if (status === Image.Error && root.loadedSource.length > 0) {
                if (("" + root.loadedSource).indexOf("file:") === 0) {
                    var key = cacheKeyFor(root.thumbUrl || root.imageUrl, "thumb")
                    Storage.removeMediaCacheEntry(key)
                    root.loadedSource = ""
                    var seq = root.loadSeq
                    var url = root.thumbUrl || root.imageUrl
                    Slack.fetchImageAsDataUrl(url, root.mimetype, function(dataUrl) {
                        if (!root || seq !== root.loadSeq)
                            return
                        if (dataUrl) {
                            root.failed = false
                            root.loadedSource = dataUrl
                            root.persistDataUrl(key, dataUrl)
                        } else {
                            root.failed = true
                        }
                    })
                    return
                }
                root.failed = true
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: image.status === Image.Ready
            onClicked: root.openRequested()
            onPressAndHold: PopupUtils.open(imageMenu, image)
        }
    }

    Component {
        id: imageMenu
        ActionSelectionPopover {
            actions: ActionList {
                Action {
                    iconName: "edit-copy"
                    text: i18n.tr("Copy link")
                    onTriggered: root.copyRequested()
                }
                Action {
                    iconName: "save"
                    text: i18n.tr("Download")
                    onTriggered: root.downloadRequested()
                }
                Action {
                    iconName: "view-fullscreen"
                    text: i18n.tr("View full screen")
                    onTriggered: root.openRequested()
                }
            }
        }
    }
}
