import QtQuick 2.7
import Lomiri.Components 1.3
import "../components"
import "../js/Models.js" as Models

Page {
    id: conversationsPage

    property var app
    property bool loading: false
    property string errorText: ""
    property var allItems: []
    property bool channelsExpanded: true
    property bool dmsExpanded: true
    property bool showAllChannels: false
    property bool showAllDms: false
    readonly property int inactiveDays: 30

    header: PageHeader {
        id: header
        title: app && app.teamName ? app.teamName : i18n.tr("Conversations")

        // First trailing action is rightmost on Lomiri
        trailingActionBar.actions: [
            Action {
                iconName: "add"
                text: i18n.tr("New conversation")
                onTriggered: conversationsPage.openNewConversation()
            },
            Action {
                iconName: "reload"
                text: i18n.tr("Refresh")
                onTriggered: conversationsPage.reload()
            },
            Action {
                iconName: "settings"
                text: i18n.tr("Settings")
                onTriggered: pageStack.push(Qt.resolvedUrl("SettingsPage.qml"), { app: conversationsPage.app })
            }
        ]

        extension: Item {
            // PageHeader reparents extension — don't anchor to header internals
            height: units.gu(6)
            width: header.width > 0 ? header.width : units.gu(40)

            TextField {
                id: searchField
                anchors {
                    fill: parent
                    leftMargin: units.gu(1)
                    rightMargin: units.gu(1)
                    topMargin: units.gu(0.5)
                    bottomMargin: units.gu(1)
                }
                placeholderText: i18n.tr("Search channels and DMs…")
                onTextChanged: conversationsPage.applyFilter()
            }
        }
    }

    ListModel {
        id: conversationModel
    }

    function matchesFilter(item, q) {
        if (!q || q.length === 0)
            return true
        return (item.title && item.title.toLowerCase().indexOf(q) !== -1)
            || (item.name && item.name.toLowerCase().indexOf(q) !== -1)
            || (item.subtitle && item.subtitle.toLowerCase().indexOf(q) !== -1)
    }

    function appendItem(it) {
        conversationModel.append({
            rowType: "item",
            sectionId: "",
            convId: it.id,
            name: it.name,
            title: it.title,
            subtitle: it.subtitle,
            isIm: it.isIm || it.isMpim,
            isMpim: it.isMpim,
            isPrivate: it.isPrivate,
            userId: it.userId,
            avatarUrl: it.avatarUrl || "",
            count: 0,
            expanded: false
        })
    }

    function appendSeeMore(sectionId, hiddenCount, showingAll) {
        var isDms = sectionId === "dms"
        conversationModel.append({
            rowType: "seeMore",
            sectionId: sectionId,
            convId: "",
            name: "",
            title: showingAll
                  ? i18n.tr("See less")
                  : i18n.tr("See more (%1)").arg(hiddenCount),
            subtitle: showingAll
                      ? (isDms
                         ? i18n.tr("Hide DMs inactive for 30+ days")
                         : i18n.tr("Hide channels inactive for 30+ days"))
                      : (isDms
                         ? i18n.tr("DMs with no activity in 30 days")
                         : i18n.tr("Channels with no activity in 30 days")),
            isIm: isDms,
            isMpim: false,
            isPrivate: false,
            userId: "",
            avatarUrl: "",
            count: hiddenCount,
            expanded: showingAll
        })
    }

    function applyFilter() {
        var q = searchField.text.trim().toLowerCase()
        var searching = q.length > 0
        var groups = Models.splitConversationGroups(allItems || [])
        var channels = []
        var dms = []
        var i

        for (i = 0; i < groups.channels.length; i++) {
            if (matchesFilter(groups.channels[i], q))
                channels.push(groups.channels[i])
        }
        for (i = 0; i < groups.dms.length; i++) {
            if (matchesFilter(groups.dms[i], q))
                dms.push(groups.dms[i])
        }

        var channelSplit = Models.splitChannelsByActivity(channels, inactiveDays)
        var dmSplit = Models.splitChannelsByActivity(dms, inactiveDays)
        var visibleChannels = (searching || showAllChannels) ? channels : channelSplit.active
        var visibleDms = (searching || showAllDms) ? dms : dmSplit.active

        conversationModel.clear()

        conversationModel.append({
            rowType: "header",
            sectionId: "channels",
            convId: "",
            name: "",
            title: i18n.tr("Channels"),
            subtitle: "",
            isIm: false,
            isMpim: false,
            isPrivate: false,
            userId: "",
            avatarUrl: "",
            count: channels.length,
            expanded: channelsExpanded
        })
        if (channelsExpanded) {
            for (i = 0; i < visibleChannels.length; i++)
                appendItem(visibleChannels[i])
            if (!searching && channelSplit.inactive.length > 0)
                appendSeeMore("channels", channelSplit.inactive.length, showAllChannels)
        }

        conversationModel.append({
            rowType: "header",
            sectionId: "dms",
            convId: "",
            name: "",
            title: i18n.tr("Direct messages"),
            subtitle: "",
            isIm: true,
            isMpim: false,
            isPrivate: false,
            userId: "",
            avatarUrl: "",
            count: dms.length,
            expanded: dmsExpanded
        })
        if (dmsExpanded) {
            for (i = 0; i < visibleDms.length; i++)
                appendItem(visibleDms[i])
            if (!searching && dmSplit.inactive.length > 0)
                appendSeeMore("dms", dmSplit.inactive.length, showAllDms)
        }
    }

    function toggleSection(sectionId) {
        if (sectionId === "channels")
            channelsExpanded = !channelsExpanded
        else if (sectionId === "dms")
            dmsExpanded = !dmsExpanded
        applyFilter()
    }

    function toggleSeeMore(sectionId) {
        if (sectionId === "dms")
            showAllDms = !showAllDms
        else
            showAllChannels = !showAllChannels
        applyFilter()
    }

    function openNewConversation() {
        pageStack.push(Qt.resolvedUrl("NewConversationPage.qml"), {
            app: conversationsPage.app
        })
    }

    function reload() {
        if (!app)
            return
        errorText = ""
        loading = true
        app.loadConversations(function(ok, items, message) {
            loading = false
            if (!ok) {
                errorText = message || i18n.tr("Failed to load conversations")
                allItems = []
                conversationModel.clear()
                return
            }
            allItems = items || []
            applyFilter()
        })
    }

    Component.onCompleted: reload()

    onVisibleChanged: {
        if (visible && app && app.pendingConversationsReload) {
            app.pendingConversationsReload = false
            reload()
        }
    }

    Item {
        id: body
        anchors {
            fill: parent
            topMargin: header.height
        }

        ActivityIndicator {
            anchors.centerIn: parent
            running: loading
            visible: running && conversationModel.count === 0
        }

        Label {
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                margins: units.gu(2)
            }
            visible: loading && conversationModel.count === 0
            text: i18n.tr("Loading conversations…")
            color: theme.palette.normal.backgroundSecondaryText
            fontSize: "small"
        }

        Label {
            anchors.centerIn: parent
            width: parent.width - units.gu(4)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            visible: !loading && errorText.length > 0
            color: theme.palette.normal.negative
            text: errorText
        }

        Label {
            anchors.centerIn: parent
            width: parent.width - units.gu(4)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            visible: !loading && errorText.length === 0 && allItems.length === 0
            color: theme.palette.normal.backgroundSecondaryText
            text: i18n.tr("No conversations yet. Tap + to message someone or join a channel.")
        }

        ListView {
            id: listView
            anchors.fill: parent
            clip: true
            model: conversationModel
            visible: conversationModel.count > 0

            delegate: Item {
                width: listView.width
                height: rowType === "header" ? units.gu(5)
                      : (rowType === "seeMore" ? units.gu(6) : units.gu(7))

                SectionHeader {
                    anchors.fill: parent
                    visible: rowType === "header"
                    titleText: title
                    count: count
                    expanded: expanded
                    onToggled: conversationsPage.toggleSection(sectionId)
                }

                ListItem {
                    anchors.fill: parent
                    visible: rowType === "seeMore"
                    onClicked: conversationsPage.toggleSeeMore(model.sectionId)

                    ListItemLayout {
                        // Use model.* — bare "title"/"subtitle" resolve to ListItemLayout's Labels
                        title.text: model.title
                        subtitle.text: model.subtitle
                        title.color: theme.palette.normal.activity
                    }
                }

                ConversationDelegate {
                    anchors.fill: parent
                    visible: rowType === "item"
                    titleText: model.title
                    subtitleText: model.subtitle
                    isIm: model.isIm
                    isPrivate: model.isPrivate
                    avatarUrl: model.avatarUrl || ""
                    onClicked: {
                        pageStack.push(Qt.resolvedUrl("ChatPage.qml"), {
                            app: conversationsPage.app,
                            channelId: model.convId,
                            channelTitle: model.title
                        })
                    }
                }
            }
        }
    }

    BottomEdge {
        id: newChatBottomEdge
        height: parent.height
        preloadContent: false
        hint {
            text: i18n.tr("New conversation")
            iconName: "add"
        }
        contentUrl: Qt.resolvedUrl("NewConversationPage.qml")
        onContentItemChanged: {
            if (!contentItem)
                return
            contentItem.width = Qt.binding(function() { return newChatBottomEdge.width })
            contentItem.height = Qt.binding(function() { return newChatBottomEdge.height })
            contentItem.app = conversationsPage.app
            contentItem.bottomEdgeHost = newChatBottomEdge
        }
        onCommitStarted: {
            if (contentItem) {
                contentItem.app = conversationsPage.app
                contentItem.bottomEdgeHost = newChatBottomEdge
            }
        }
    }
}
