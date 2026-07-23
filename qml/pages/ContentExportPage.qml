import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Content 1.3

Page {
    id: exportPage

    property string fileUrl: ""
    property var activeTransfer

    signal completed()
    signal cancelled()

    header: PageHeader {
        id: header
        title: i18n.tr("Save image")
        leadingActionBar.actions: [
            Action {
                iconName: "back"
                text: i18n.tr("Cancel")
                onTriggered: {
                    exportPage.cancelled()
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
        contentType: ContentType.Pictures
        handler: ContentHandler.Destination
        showTitle: false

        onPeerSelected: {
            peer.selectionType = ContentTransfer.Single
            exportPage.activeTransfer = peer.request()
            exportPage.activeTransfer.stateChanged.connect(function() {
                if (!exportPage.activeTransfer)
                    return
                if (exportPage.activeTransfer.state === ContentTransfer.InProgress) {
                    exportPage.activeTransfer.items = [
                        resultComponent.createObject(exportPage, { url: exportPage.fileUrl })
                    ]
                    exportPage.activeTransfer.state = ContentTransfer.Charged
                } else if (exportPage.activeTransfer.state === ContentTransfer.Charged
                        || exportPage.activeTransfer.state === ContentTransfer.Collected) {
                    exportPage.activeTransfer = null
                    exportPage.completed()
                    pageStack.pop()
                } else if (exportPage.activeTransfer.state === ContentTransfer.Aborted) {
                    exportPage.activeTransfer = null
                    exportPage.cancelled()
                    pageStack.pop()
                }
            })
        }

        onCancelPressed: {
            exportPage.cancelled()
            pageStack.pop()
        }
    }

    ContentTransferHint {
        anchors.fill: parent
        activeTransfer: exportPage.activeTransfer
    }

    Component {
        id: resultComponent
        ContentItem {}
    }
}
