import QtQuick 2.7
import QtMultimedia 5.0
import Lomiri.Components 1.3
import UTSlack 1.0
import "../js/SlackClient.js" as Slack

// Inline Slack video / audio / generic file attachment.
// Slack private URLs need Bearer auth; MediaPlayer cannot send headers, so we
// download via MediaCache and play a local file:// URL.
Item {
    id: root
    width: parent ? parent.width : units.gu(40)
    height: {
        if (kind === "video")
            return videoBox.height
        if (kind === "audio")
            return audioBox.height
        return fileBox.height
    }

    property string kind: "file"       // video | audio | file
    property string mediaUrl: ""
    property string thumbUrl: ""
    property string title: ""
    property string mimetype: ""
    property string fileId: ""
    property int mediaWidth: 0
    property int mediaHeight: 0
    property int byteSize: 0
    property string prettyType: ""
    property bool needsAuth: true

    property string localUrl: ""
    property bool downloading: false
    property string loadError: ""

    signal openRequested(var fileInfo)
    signal childPressChanged(bool pressed)

    readonly property string cacheKey: {
        if (fileId)
            return fileId
        return mediaUrl
    }

    readonly property real videoAspect: {
        if (mediaWidth > 0 && mediaHeight > 0)
            return mediaWidth / mediaHeight
        return 16 / 9
    }

    function fileInfo() {
        return {
            url: mediaUrl,
            thumb: thumbUrl,
            name: title,
            mimetype: mimetype,
            kind: kind,
            id: fileId,
            size: byteSize,
            prettyType: prettyType,
            needsAuth: needsAuth
        }
    }

    function extensionFor() {
        var mime = (mimetype || "").toLowerCase()
        var name = (title || "").toLowerCase()
        if (mime.indexOf("video/mp4") === 0 || /\.mp4$/.test(name))
            return "mp4"
        if (mime.indexOf("video/quicktime") === 0 || /\.mov$/.test(name))
            return "mov"
        if (mime.indexOf("video/webm") === 0 || /\.webm$/.test(name))
            return "webm"
        if (mime.indexOf("video/3gpp") === 0 || /\.3gp$/.test(name))
            return "3gp"
        if (mime.indexOf("audio/mpeg") === 0 || /\.mp3$/.test(name))
            return "mp3"
        if (mime.indexOf("audio/mp4") === 0 || /\.m4a$/.test(name))
            return "m4a"
        if (mime.indexOf("audio/aac") === 0 || /\.aac$/.test(name))
            return "aac"
        if (mime.indexOf("audio/ogg") === 0 || /\.ogg$/.test(name))
            return "ogg"
        if (mime.indexOf("audio/wav") === 0 || /\.wav$/.test(name))
            return "wav"
        if (mime.indexOf("video/") === 0)
            return "mp4"
        if (mime.indexOf("audio/") === 0)
            return "mp3"
        var dot = name.lastIndexOf(".")
        if (dot > 0 && dot < name.length - 1)
            return name.substring(dot + 1).replace(/[^a-z0-9]/g, "") || "bin"
        return "bin"
    }

    function formatTime(ms) {
        var s = Math.floor((Number(ms) || 0) / 1000)
        if (s < 0)
            s = 0
        var m = Math.floor(s / 60)
        s = s % 60
        return m + ":" + (s < 10 ? "0" : "") + s
    }

    function formatSize(bytes) {
        var n = Number(bytes) || 0
        if (n <= 0)
            return ""
        if (n < 1024)
            return n + " B"
        if (n < 1024 * 1024)
            return Math.round(n / 102.4) / 10 + " KB"
        return Math.round(n / (1024 * 102.4)) / 10 + " MB"
    }

    function stopPlayback() {
        if (videoPlayer.playbackState !== MediaPlayer.StoppedState)
            videoPlayer.stop()
        if (audioPlayer.playbackState !== MediaPlayer.StoppedState)
            audioPlayer.stop()
        videoPlayer.source = ""
        audioPlayer.source = ""
    }

    function ensureLocal(thenPlay) {
        loadError = ""
        if (!mediaUrl) {
            loadError = i18n.tr("No media URL")
            return
        }
        if (!needsAuth) {
            localUrl = mediaUrl
            if (thenPlay)
                thenPlay(localUrl)
            return
        }
        if (localUrl) {
            if (thenPlay)
                thenPlay(localUrl)
            return
        }
        if (MediaCache.has(cacheKey)) {
            localUrl = MediaCache.fileUrlFor(cacheKey)
            if (thenPlay)
                thenPlay(localUrl)
            return
        }
        downloading = true
        root._pendingPlay = thenPlay || null
        if (MediaCache.isDownloading(cacheKey))
            return
        MediaCache.download(mediaUrl, Slack.getToken(), cacheKey, extensionFor())
    }

    property var _pendingPlay: null

    Connections {
        target: MediaCache
        onDownloadFinished: {
            if (key !== root.cacheKey)
                return
            root.localUrl = fileUrl
            root.downloading = false
            root.loadError = ""
            var cb = root._pendingPlay
            root._pendingPlay = null
            if (cb)
                cb(fileUrl)
        }
        onDownloadFailed: {
            if (key !== root.cacheKey)
                return
            root.downloading = false
            root.loadError = error || i18n.tr("Download failed")
            root._pendingPlay = null
            console.log("[media] cache failed", key, error)
        }
    }

    Component.onDestruction: stopPlayback()
    onMediaUrlChanged: {
        stopPlayback()
        localUrl = ""
        loadError = ""
        downloading = false
        _pendingPlay = null
    }
    onKindChanged: stopPlayback()

    // ----- Video -----
    Rectangle {
        id: videoBox
        width: parent.width
        height: Math.round(width / root.videoAspect)
        visible: root.kind === "video"
        color: "#000000"
        radius: units.gu(0.5)
        clip: true

        VideoOutput {
            id: videoOut
            anchors.fill: parent
            source: videoPlayer
            fillMode: VideoOutput.PreserveAspectFit
            visible: videoPlayer.status >= MediaPlayer.Loaded
                     && videoPlayer.playbackState !== MediaPlayer.StoppedState
        }

        Image {
            id: poster
            anchors.fill: parent
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: true
            visible: status === Image.Ready
                     && (videoPlayer.playbackState === MediaPlayer.StoppedState
                         || videoPlayer.status < MediaPlayer.Loaded)
        }

        Component.onCompleted: {
            if (root.kind !== "video" || !root.thumbUrl)
                return
            if (!root.needsAuth) {
                poster.source = root.thumbUrl
                return
            }
            Slack.fetchImageAsDataUrl(root.thumbUrl, "image/jpeg", function(dataUrl) {
                if (dataUrl)
                    poster.source = dataUrl
            })
        }

        MediaPlayer {
            id: videoPlayer
            autoPlay: false
            autoLoad: false
            onError: console.log("[media] video error", errorString, root.localUrl)
        }

        AbstractButton {
            anchors.fill: parent
            onPressedChanged: root.childPressChanged(pressed)
            onClicked: {
                root.ensureLocal(function(url) {
                    if (!url)
                        return
                    if (videoPlayer.source.toString() !== url)
                        videoPlayer.source = url
                    if (videoPlayer.playbackState === MediaPlayer.PlayingState)
                        videoPlayer.pause()
                    else
                        videoPlayer.play()
                })
            }

            Rectangle {
                anchors.centerIn: parent
                width: units.gu(6)
                height: units.gu(6)
                radius: width / 2
                color: "#88000000"
                visible: !root.downloading
                         && (videoPlayer.playbackState !== MediaPlayer.PlayingState
                             || videoChrome.opacity > 0)

                Icon {
                    anchors.centerIn: parent
                    width: units.gu(3)
                    height: units.gu(3)
                    name: videoPlayer.playbackState === MediaPlayer.PlayingState
                          ? "media-playback-pause"
                          : "media-playback-start"
                    color: "#FFFFFF"
                }
            }
        }

        Item {
            id: videoChrome
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            height: units.gu(5)
            opacity: videoPlayer.playbackState === MediaPlayer.PlayingState ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 150 } }

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#00000000" }
                    GradientStop { position: 1.0; color: "#AA000000" }
                }
            }

            Row {
                anchors {
                    fill: parent
                    margins: units.gu(0.75)
                }
                spacing: units.gu(0.75)

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.formatTime(videoPlayer.position)
                    color: "#FFFFFF"
                    fontSize: "x-small"
                }

                Slider {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - units.gu(10)
                    minimumValue: 0
                    maximumValue: Math.max(1, videoPlayer.duration)
                    value: videoPlayer.position
                    live: true
                    onPressedChanged: root.childPressChanged(pressed)
                    onValueChanged: {
                        if (pressed && videoPlayer.seekable)
                            videoPlayer.seek(value)
                    }
                }

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.formatTime(videoPlayer.duration)
                    color: "#FFFFFF"
                    fontSize: "x-small"
                }
            }
        }

        ActivityIndicator {
            anchors.centerIn: parent
            running: root.downloading
                     || videoPlayer.status === MediaPlayer.Loading
                     || videoPlayer.status === MediaPlayer.Buffering
            visible: running
        }

        Label {
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                margins: units.gu(1)
            }
            visible: root.loadError !== "" || videoPlayer.error !== MediaPlayer.NoError
            wrapMode: Text.Wrap
            color: "#FFCCCC"
            fontSize: "x-small"
            text: root.loadError || i18n.tr("Couldn't play video")
        }
    }

    // ----- Audio -----
    Rectangle {
        id: audioBox
        width: parent.width
        height: units.gu(8)
        visible: root.kind === "audio"
        radius: units.gu(0.75)
        color: theme.palette.normal.foreground
        border.width: units.dp(1)
        border.color: theme.palette.normal.base

        MediaPlayer {
            id: audioPlayer
            autoPlay: false
            autoLoad: false
            onError: console.log("[media] audio error", errorString, root.localUrl)
        }

        Row {
            anchors {
                fill: parent
                margins: units.gu(1)
            }
            spacing: units.gu(1)

            AbstractButton {
                id: audioPlayBtn
                anchors.verticalCenter: parent.verticalCenter
                width: units.gu(5)
                height: units.gu(5)
                onPressedChanged: root.childPressChanged(pressed)
                onClicked: {
                    root.ensureLocal(function(url) {
                        if (!url)
                            return
                        if (audioPlayer.source.toString() !== url)
                            audioPlayer.source = url
                        if (audioPlayer.playbackState === MediaPlayer.PlayingState)
                            audioPlayer.pause()
                        else
                            audioPlayer.play()
                    })
                }

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: theme.palette.normal.activity
                }

                Icon {
                    anchors.centerIn: parent
                    width: units.gu(2.5)
                    height: units.gu(2.5)
                    name: root.downloading
                          ? "sync"
                          : (audioPlayer.playbackState === MediaPlayer.PlayingState
                             ? "media-playback-pause"
                             : "media-playback-start")
                    color: "#FFFFFF"
                }

                ActivityIndicator {
                    anchors.centerIn: parent
                    running: root.downloading
                    visible: running
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - units.gu(6)
                spacing: units.gu(0.4)

                Label {
                    width: parent.width
                    text: root.title || i18n.tr("Audio")
                    elide: Text.ElideMiddle
                    fontSize: "small"
                    color: theme.palette.normal.backgroundText
                }

                Row {
                    width: parent.width
                    spacing: units.gu(0.5)

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.formatTime(audioPlayer.position)
                        fontSize: "x-small"
                        color: theme.palette.normal.backgroundSecondaryText
                    }

                    Slider {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - units.gu(8)
                        minimumValue: 0
                        maximumValue: Math.max(1, audioPlayer.duration)
                        value: audioPlayer.position
                        live: true
                        onPressedChanged: root.childPressChanged(pressed)
                        onValueChanged: {
                            if (pressed && audioPlayer.seekable)
                                audioPlayer.seek(value)
                        }
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.formatTime(audioPlayer.duration)
                        fontSize: "x-small"
                        color: theme.palette.normal.backgroundSecondaryText
                    }
                }

                Label {
                    visible: root.loadError !== "" || audioPlayer.error !== MediaPlayer.NoError
                    width: parent.width
                    text: root.loadError || i18n.tr("Couldn't play audio")
                    fontSize: "x-small"
                    color: theme.palette.normal.negative
                }
            }
        }
    }

    // ----- Generic file -----
    AbstractButton {
        id: fileBox
        width: parent.width
        height: units.gu(6)
        visible: root.kind !== "video" && root.kind !== "audio"
        onPressedChanged: root.childPressChanged(pressed)
        onClicked: root.openRequested(root.fileInfo())

        Rectangle {
            anchors.fill: parent
            radius: units.gu(0.75)
            color: theme.palette.normal.foreground
            border.width: units.dp(1)
            border.color: theme.palette.normal.base
        }

        Row {
            anchors {
                fill: parent
                leftMargin: units.gu(1)
                rightMargin: units.gu(1)
            }
            spacing: units.gu(1)

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                width: units.gu(3)
                height: units.gu(3)
                name: "document-open"
                color: theme.palette.normal.backgroundText
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - units.gu(5)
                spacing: units.gu(0.1)

                Label {
                    width: parent.width
                    text: root.title || i18n.tr("Attachment")
                    elide: Text.ElideMiddle
                    fontSize: "small"
                    color: theme.palette.normal.backgroundText
                }

                Label {
                    width: parent.width
                    text: {
                        var parts = []
                        if (root.prettyType)
                            parts.push(root.prettyType)
                        else
                            parts.push(i18n.tr("File"))
                        var sz = root.formatSize(root.byteSize)
                        if (sz)
                            parts.push(sz)
                        return parts.join(" · ")
                    }
                    elide: Text.ElideRight
                    fontSize: "x-small"
                    color: theme.palette.normal.backgroundSecondaryText
                }
            }
        }
    }
}
