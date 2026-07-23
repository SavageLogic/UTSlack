import QtQuick 2.7
import Lomiri.Components 1.3
import Qt.labs.platform 1.0 as Labs
import "../js/SlackClient.js" as Slack

// Invisible helper: load an image source, write a PNG into the app cache, return file:// URL.
Item {
    id: root
    width: 0
    height: 0
    visible: false

    property string pendingName: "image.png"
    property var pendingCallback: null
    property bool waiting: false

    Image {
        id: img
        asynchronous: true
        cache: false
        onStatusChanged: {
            if (!root.waiting)
                return
            if (status === Image.Ready)
                root.grabAndSave()
            else if (status === Image.Error)
                root.finish(null, i18n.tr("Couldn't decode image"))
        }
    }

    function cacheDir() {
        try {
            var p = Labs.StandardPaths.writableLocation(Labs.StandardPaths.CacheLocation)
            if (p && ("" + p).length > 0)
                return ("" + p).replace(/\/$/, "")
        } catch (e) {}
        return "/tmp"
    }

    function safeName(name) {
        var n = (name || "image").replace(/[\/\\?%*:|"<>]/g, "_")
        if (!/\.(png|jpe?g|gif|webp|bmp)$/i.test(n))
            n += ".png"
        // grabToImage always writes PNG
        n = n.replace(/\.(jpe?g|gif|webp|bmp)$/i, ".png")
        return n
    }

    function finish(fileUrl, error) {
        waiting = false
        var cb = pendingCallback
        pendingCallback = null
        img.source = ""
        if (cb)
            cb(fileUrl || "", error || "")
    }

    function grabAndSave() {
        var path = cacheDir() + "/" + safeName(pendingName)
        img.grabToImage(function(result) {
            if (!result) {
                finish(null, i18n.tr("Couldn't capture image"))
                return
            }
            var ok = false
            try {
                ok = result.saveToFile(path)
            } catch (e) {
                console.log("[save] saveToFile failed", e)
            }
            if (!ok) {
                finish(null, i18n.tr("Couldn't write image file"))
                return
            }
            var url = path.indexOf("file:") === 0 ? path : ("file://" + path)
            finish(url, "")
        })
    }

    // source may be data: or http(s); for private Slack URLs pass a data URL already fetched
    function saveImageSource(source, fileName, callback) {
        if (!source) {
            if (callback)
                callback("", i18n.tr("No image to save"))
            return
        }
        pendingName = fileName || "image.png"
        pendingCallback = callback
        waiting = true
        if (img.source === source && img.status === Image.Ready) {
            grabAndSave()
            return
        }
        img.source = source
    }

    // Prefer full URL; fetch with auth when needed, then save
    function saveFromUrls(imageUrl, thumbUrl, needsAuth, mimetype, fileName, callback) {
        var preferred = imageUrl || thumbUrl
        if (!preferred) {
            if (callback)
                callback("", i18n.tr("No image to save"))
            return
        }
        if (!needsAuth && ("" + preferred).indexOf("http") === 0) {
            saveImageSource(preferred, fileName, callback)
            return
        }
        Slack.fetchImageAsDataUrl(preferred, mimetype || "image/jpeg", function(dataUrl) {
            if (!dataUrl && imageUrl && imageUrl !== preferred) {
                Slack.fetchImageAsDataUrl(imageUrl, mimetype || "image/jpeg", function(dataUrl2) {
                    if (!dataUrl2) {
                        if (callback)
                            callback("", i18n.tr("Couldn't download image"))
                        return
                    }
                    saveImageSource(dataUrl2, fileName, callback)
                })
                return
            }
            if (!dataUrl) {
                if (callback)
                    callback("", i18n.tr("Couldn't download image"))
                return
            }
            saveImageSource(dataUrl, fileName, callback)
        })
    }
}
