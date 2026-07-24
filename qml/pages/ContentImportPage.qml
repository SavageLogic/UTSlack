import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Content 1.3

Page {
    id: pickerPage
    property var activeTransfer
    property int contentType: ContentType.Pictures
    property string pageTitle: contentType === ContentType.Documents
                               ? i18n.tr("Choose a file")
                               : i18n.tr("Choose media")

    signal imported(string fileUrl)
    signal cancelled()

    header: PageHeader {
        id: header
        title: pickerPage.pageTitle
        leadingActionBar.actions: [
            Action {
                iconName: "back"
                text: i18n.tr("Cancel")
                onTriggered: {
                    pickerPage.cancelled()
                    pageStack.pop()
                }
            }
        ]
    }

    ContentPeerPicker {
        anchors {
            fill: parent
            topMargin: header.height
        }
        contentType: pickerPage.contentType
        handler: ContentHandler.Source
        showTitle: false

        onPeerSelected: {
            peer.selectionType = ContentTransfer.Single
            pickerPage.activeTransfer = peer.request()
            pickerPage.activeTransfer.stateChanged.connect(function() {
                if (!pickerPage.activeTransfer)
                    return
                if (pickerPage.activeTransfer.state === ContentTransfer.Charged) {
                    var items = pickerPage.activeTransfer.items
                    if (items && items.length > 0 && items[0].url) {
                        pickerPage.imported("" + items[0].url)
                    } else {
                        pickerPage.cancelled()
                    }
                    pickerPage.activeTransfer = null
                    pageStack.pop()
                } else if (pickerPage.activeTransfer.state === ContentTransfer.Aborted) {
                    pickerPage.activeTransfer = null
                    pickerPage.cancelled()
                    pageStack.pop()
                }
            })
        }

        onCancelPressed: {
            pickerPage.cancelled()
            pageStack.pop()
        }
    }

    ContentTransferHint {
        anchors.fill: parent
        activeTransfer: pickerPage.activeTransfer
    }
}
