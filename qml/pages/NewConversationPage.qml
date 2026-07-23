import QtQuick 2.7
import Lomiri.Components 1.3
import "../components"

Page {
    id: newConversationPage

    property var app
    property var bottomEdgeHost: null
    // BottomEdge content is not on the PageStack — callers must set this.
    property var navigationStack: null
    property bool loading: false
    property bool opening: false
    property string errorText: ""
    property string mode: "people" // people | channels
    property var people: []
    property var channels: []

    header: PageHeader {
        id: header
        title: i18n.tr("New conversation")
    }

    ListModel {
        id: pickerModel
    }

    function stack() {
        return navigationStack || pageStack
    }

    function matchesFilter(item, q) {
        if (!q || q.length === 0)
            return true
        return (item.title && item.title.toLowerCase().indexOf(q) !== -1)
            || (item.subtitle && item.subtitle.toLowerCase().indexOf(q) !== -1)
            || (item.name && item.name.toLowerCase().indexOf(q) !== -1)
    }

    function rebuild() {
        var source = mode === "people" ? people : channels
        var q = searchField.text.trim().toLowerCase()
        pickerModel.clear()
        for (var i = 0; i < source.length; i++) {
            var it = source[i]
            if (!matchesFilter(it, q))
                continue
            pickerModel.append({
                itemId: it.id,
                title: it.title,
                subtitle: it.subtitle,
                kind: it.kind,
                isMember: !!it.isMember,
                hasConversation: !!it.hasConversation,
                conversationId: it.conversationId || "",
                isIm: it.kind === "user",
                isPrivate: !!it.isPrivate,
                avatarUrl: it.avatarUrl || ""
            })
        }
    }

    function reload() {
        if (!app)
            return
        errorText = ""
        loading = true
        app.loadPickerData(function(ok, data, message) {
            loading = false
            if (!ok) {
                errorText = message || i18n.tr("Failed to load people and channels")
                people = []
                channels = []
                pickerModel.clear()
                return
            }
            people = (data && data.people) ? data.people : []
            channels = (data && data.channels) ? data.channels : []
            rebuild()
        })
    }

    function openChat(channelId, title) {
        var theApp = newConversationPage.app
        var host = newConversationPage.bottomEdgeHost
        var stack = newConversationPage.stack()
        if (theApp)
            theApp.pendingConversationsReload = true
        if (!stack) {
            errorText = i18n.tr("Couldn't open conversation")
            opening = false
            return
        }

        if (host) {
            // Push first — collapsing the BottomEdge destroys this page.
            stack.push(Qt.resolvedUrl("ChatPage.qml"), {
                app: theApp,
                channelId: channelId,
                channelTitle: title
            })
            host.collapse()
        } else {
            stack.pop()
            stack.push(Qt.resolvedUrl("ChatPage.qml"), {
                app: theApp,
                channelId: channelId,
                channelTitle: title
            })
        }
    }

    function selectItem(item) {
        if (opening || !app)
            return
        errorText = ""
        opening = true

        if (item.kind === "user") {
            if (item.hasConversation && item.conversationId) {
                opening = false
                openChat(item.conversationId, item.title)
                return
            }
            app.openDirectMessage(item.itemId, function(ok, conv, message) {
                opening = false
                if (!ok) {
                    errorText = message || i18n.tr("Could not open DM")
                    return
                }
                openChat(conv.id, conv.title || item.title)
            })
            return
        }

        app.openChannelConversation(item.itemId, item.isMember, function(ok, conv, message) {
            opening = false
            if (!ok) {
                errorText = message || i18n.tr("Could not open channel")
                return
            }
            openChat(conv.id, conv.title || item.title)
        })
    }

    Component.onCompleted: reload()
    onAppChanged: {
        if (app)
            reload()
    }

    Column {
        id: topBar
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            topMargin: header.height
        }
        spacing: units.gu(1)

        Item {
            width: parent.width
            height: units.gu(5)

            Row {
                anchors {
                    fill: parent
                    margins: units.gu(1)
                }
                spacing: units.gu(1)

                Button {
                    width: (parent.width - units.gu(1)) / 2
                    text: i18n.tr("People")
                    color: mode === "people" ? theme.palette.normal.positive : theme.palette.normal.base
                    onClicked: {
                        mode = "people"
                        rebuild()
                    }
                }
                Button {
                    width: (parent.width - units.gu(1)) / 2
                    text: i18n.tr("Channels")
                    color: mode === "channels" ? theme.palette.normal.positive : theme.palette.normal.base
                    onClicked: {
                        mode = "channels"
                        rebuild()
                    }
                }
            }
        }

        TextField {
            id: searchField
            anchors {
                left: parent.left
                right: parent.right
                margins: units.gu(1)
            }
            width: parent.width - units.gu(2)
            placeholderText: mode === "people"
                             ? i18n.tr("Search people…")
                             : i18n.tr("Search channels…")
            onTextChanged: newConversationPage.rebuild()
        }

        Label {
            anchors {
                left: parent.left
                right: parent.right
                margins: units.gu(2)
            }
            width: parent.width - units.gu(4)
            visible: errorText.length > 0
            wrapMode: Text.Wrap
            color: theme.palette.normal.negative
            text: errorText
        }
    }

    Item {
        anchors {
            top: topBar.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            topMargin: units.gu(1)
        }

        ActivityIndicator {
            anchors.centerIn: parent
            running: loading || opening
            visible: running
        }

        Label {
            anchors.centerIn: parent
            width: parent.width - units.gu(4)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            visible: !loading && !opening && pickerModel.count === 0 && errorText.length === 0
            color: theme.palette.normal.backgroundSecondaryText
            text: mode === "people"
                  ? i18n.tr("No people found.")
                  : i18n.tr("No channels found.")
        }

        ListView {
            id: listView
            anchors.fill: parent
            clip: true
            model: pickerModel
            visible: !loading && !opening && pickerModel.count > 0

            delegate: ConversationDelegate {
                width: listView.width
                titleText: model.title
                subtitleText: model.subtitle
                isIm: model.isIm
                isPrivate: model.isPrivate
                avatarUrl: model.avatarUrl || ""
                onClicked: {
                    newConversationPage.selectItem({
                        itemId: model.itemId,
                        title: model.title,
                        kind: model.kind,
                        isMember: model.isMember,
                        hasConversation: model.hasConversation,
                        conversationId: model.conversationId
                    })
                }
            }
        }
    }
}
