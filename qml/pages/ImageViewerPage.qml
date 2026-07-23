import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import "../components"
import "../js/SlackClient.js" as Slack

Page {
    id: viewerPage

    property string imageUrl: ""
    property string thumbUrl: ""
    property string mimetype: "image/jpeg"
    property bool needsAuth: true
    property string title: ""
    property string loadedSource: ""

    property string displaySource: ""
    property bool loading: false
    property bool saving: false
    property string errorText: ""

    header: PageHeader {
        id: header
        title: viewerPage.title || i18n.tr("Image")
        trailingActionBar.actions: [
            Action {
                iconName: "edit-copy"
                text: i18n.tr("Copy link")
                enabled: !viewerPage.saving && (viewerPage.displaySource.length > 0 || viewerPage.imageUrl.length > 0)
                onTriggered: viewerPage.copyImage()
            },
            Action {
                iconName: "save"
                text: i18n.tr("Download")
                enabled: !viewerPage.saving && (viewerPage.displaySource.length > 0 || viewerPage.imageUrl.length > 0)
                onTriggered: viewerPage.downloadImage()
            }
        ]
    }

    ImageSaver {
        id: imageSaver
    }

    TextEdit {
        id: clipboardHelper
        visible: false
        text: ""
    }

    function loadFull() {
        errorText = ""
        if (loadedSource && loadedSource.length > 0) {
            displaySource = loadedSource
            // Still try to upgrade to full-res when we only have a thumb data URL
            if (imageUrl && imageUrl.length > 0 && needsAuth && thumbUrl && thumbUrl !== imageUrl)
                fetchPreferred()
            return
        }
        fetchPreferred()
    }

    function fetchPreferred() {
        var url = imageUrl || thumbUrl
        if (!url) {
            errorText = i18n.tr("No image")
            return
        }
        if (!needsAuth && url.indexOf("http") === 0) {
            displaySource = url
            return
        }
        loading = true
        Slack.fetchImageAsDataUrl(url, mimetype, function(dataUrl) {
            if (dataUrl) {
                displaySource = dataUrl
                loading = false
                return
            }
            if (imageUrl && thumbUrl && imageUrl !== thumbUrl) {
                Slack.fetchImageAsDataUrl(thumbUrl, mimetype, function(dataUrl2) {
                    loading = false
                    if (dataUrl2)
                        displaySource = dataUrl2
                    else
                        errorText = i18n.tr("Couldn't load image")
                })
            } else {
                loading = false
                errorText = i18n.tr("Couldn't load image")
            }
        })
    }

    function downloadImage() {
        if (saving)
            return
        saving = true
        errorText = ""
        var name = title || "slack-image.png"
        function afterSave(fileUrl, err) {
            saving = false
            if (!fileUrl) {
                errorText = err || i18n.tr("Couldn't save image")
                return
            }
            pageStack.push(Qt.resolvedUrl("ContentExportPage.qml"), { fileUrl: fileUrl })
        }
        if (displaySource && displaySource.length > 0) {
            imageSaver.saveImageSource(displaySource, name, afterSave)
        } else {
            imageSaver.saveFromUrls(imageUrl, thumbUrl, needsAuth, mimetype, name, afterSave)
        }
    }

    function copyImage() {
        if (saving)
            return
        saving = true
        errorText = ""

        var url = imageUrl || thumbUrl
        if (!url) {
            saving = false
            errorText = i18n.tr("No image to copy")
            return
        }
        if (needsAuth) {
            saving = false
            errorText = i18n.tr("Private Slack images can't be copied yet — use Download")
            return
        }
        clipboardHelper.text = url
        clipboardHelper.selectAll()
        clipboardHelper.copy()
        saving = false
    }


    Component.onCompleted: loadFull()

    Rectangle {
        anchors.fill: parent
        color: "#000000"

        ActivityIndicator {
            anchors.centerIn: parent
            running: viewerPage.loading || viewerPage.saving
            visible: running
        }

        Label {
            anchors.centerIn: parent
            width: parent.width - units.gu(4)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            visible: errorText.length > 0 && !loading
            color: "#FFFFFF"
            text: errorText
        }

        Flickable {
            id: flick
            anchors {
                fill: parent
                topMargin: header.height
            }
            contentWidth: width
            contentHeight: height
            clip: true
            interactive: image.paintedWidth > width || image.paintedHeight > height

            PinchArea {
                width: Math.max(flick.contentWidth, flick.width)
                height: Math.max(flick.contentHeight, flick.height)
                pinch.target: image
                pinch.minimumScale: 1.0
                pinch.maximumScale: 4.0
                pinch.dragAxis: Pinch.XAndYAxis

                onPinchFinished: {
                    flick.returnToBounds()
                }

                Image {
                    id: image
                    anchors.centerIn: parent
                    width: flick.width
                    height: flick.height
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: true
                    source: viewerPage.displaySource
                    visible: source.toString().length > 0 && !viewerPage.loading

                    MouseArea {
                        anchors.fill: parent
                        propagateComposedEvents: true
                        onPressAndHold: PopupUtils.open(downloadPopover, image)
                        // Single tap does not close — use header back (avoids fighting pinch)
                    }
                }
            }
        }
    }

    Component {
        id: downloadPopover
        ActionSelectionPopover {
            actions: ActionList {
                Action {
                    iconName: "edit-copy"
                    text: i18n.tr("Copy link")
                    onTriggered: viewerPage.copyImage()
                }
                Action {
                    iconName: "save"
                    text: i18n.tr("Download")
                    onTriggered: viewerPage.downloadImage()
                }
            }
        }
    }
}
