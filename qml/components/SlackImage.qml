import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import "../js/SlackClient.js" as Slack

Item {
    id: root
    width: parent ? Math.min(parent.width, units.gu(40)) : units.gu(40)
    height: {
        if (root.failed)
            return errorLabel.implicitHeight + units.gu(2)
        if (busy.visible)
            return units.gu(12)
        if (image.status === Image.Ready && image.sourceSize.width > 0)
            return Math.ceil(root.width * image.sourceSize.height / image.sourceSize.width)
        return units.gu(12)
    }

    property string imageUrl: ""
    property string thumbUrl: ""
    property string mimetype: "image/jpeg"
    property bool needsAuth: true
    property string title: ""

    property string loadedSource: ""
    property bool failed: false
    property int loadSeq: 0

    signal openRequested()
    signal downloadRequested()
    signal copyRequested()

    function imageInfo() {
        return {
            url: root.imageUrl,
            thumb: root.thumbUrl,
            mimetype: root.mimetype,
            needsAuth: root.needsAuth,
            name: root.title,
            loadedSource: root.loadedSource
        }
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
            loadedSource = url
            return
        }
        Slack.fetchImageAsDataUrl(url, root.mimetype, function(dataUrl) {
            if (seq !== root.loadSeq)
                return
            if (!dataUrl) {
                if (root.imageUrl && root.imageUrl !== url) {
                    Slack.fetchImageAsDataUrl(root.imageUrl, root.mimetype, function(dataUrl2) {
                        if (seq !== root.loadSeq)
                            return
                        if (dataUrl2)
                            loadedSource = dataUrl2
                        else
                            failed = true
                    })
                } else {
                    failed = true
                }
                return
            }
            loadedSource = dataUrl
        })
    }

    Component.onCompleted: startLoad()
    onImageUrlChanged: startLoad()
    onThumbUrlChanged: startLoad()

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
        width: parent.width
        height: (status === Image.Ready && sourceSize.width > 0)
                ? Math.ceil(width * sourceSize.height / sourceSize.width)
                : 0
        visible: root.loadedSource.length > 0 && !root.failed
        source: root.loadedSource
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: true
        onStatusChanged: {
            if (status === Image.Error && root.loadedSource.length > 0)
                root.failed = true
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
