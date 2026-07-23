import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import "../components"
import "../js/Models.js" as Models
import "../js/Storage.js" as Storage

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

    property string menuChannelId: ""
    property string menuNotifyMode: "all"

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

    function appendItem(it, sectionId) {
        var hidden = Storage.isConversationHidden(it.id)
        conversationModel.append({
            rowType: "item",
            sectionId: sectionId || "",
            convId: it.id,
            name: it.name,
            title: it.title,
            subtitle: it.subtitle,
            isIm: it.isIm || it.isMpim,
            isMpim: it.isMpim,
            isPrivate: it.isPrivate,
            userId: it.userId,
            avatarUrl: it.avatarUrl || "",
            hasUnread: !!it.hasUnread,
            isHidden: hidden,
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
                  : i18n.tr("See More (%1)").arg(hiddenCount),
            subtitle: showingAll
                      ? (isDms
                         ? i18n.tr("Hide inactive and hidden DMs")
                         : i18n.tr("Hide inactive and hidden channels"))
                      : (isDms
                         ? i18n.tr("Inactive or hidden DMs")
                         : i18n.tr("Inactive or hidden channels")),
            isIm: isDms,
            isMpim: false,
            isPrivate: false,
            userId: "",
            avatarUrl: "",
            hasUnread: false,
            isHidden: false,
            count: hiddenCount,
            expanded: showingAll
        })
    }

    function appendSection(items, sectionId, titleText, expanded, showAll) {
        var filtered = []
        var q = searchField.text.trim().toLowerCase()
        var searching = q.length > 0
        var i
        for (i = 0; i < items.length; i++) {
            if (matchesFilter(items[i], q))
                filtered.push(items[i])
        }

        var split = Models.splitPrimaryAndSecondary(filtered, inactiveDays, Storage.getHiddenMap())
        var visible = (searching || showAll)
                      ? filtered
                      : split.primary

        conversationModel.append({
            rowType: "header",
            sectionId: sectionId,
            convId: "",
            name: "",
            title: titleText,
            subtitle: "",
            isIm: sectionId === "dms",
            isMpim: false,
            isPrivate: false,
            userId: "",
            avatarUrl: "",
            hasUnread: false,
            isHidden: false,
            count: filtered.length,
            expanded: expanded
        })
        if (!expanded)
            return
        for (i = 0; i < visible.length; i++)
            appendItem(visible[i], sectionId)
        if (!searching && split.secondary.length > 0)
            appendSeeMore(sectionId, split.secondary.length, showAll)
    }

    function applyFilter() {
        var groups = Models.splitConversationGroups(allItems || [])
        conversationModel.clear()
        appendSection(groups.channels || [], "channels", i18n.tr("Channels"),
                      channelsExpanded, showAllChannels)
        appendSection(groups.dms || [], "dms", i18n.tr("Direct messages"),
                      dmsExpanded, showAllDms)
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

    function hideConversation(channelId) {
        if (!channelId)
            return
        if (app && app.hideConversation)
            app.hideConversation(channelId)
        else
            Storage.setConversationHidden(channelId, true)
        applyFilter()
    }

    function unhideConversation(channelId) {
        if (!channelId)
            return
        if (app && app.unhideConversation)
            app.unhideConversation(channelId)
        else
            Storage.setConversationHidden(channelId, false)
        applyFilter()
    }

    function openNotifyMenu(item, channelId) {
        if (!channelId)
            return
        menuChannelId = channelId
        menuNotifyMode = (app && app.getChannelNotifyMode)
                         ? app.getChannelNotifyMode(channelId)
                         : Storage.getEffectiveNotifyMode(channelId)
        PopupUtils.open(notifyMenuComponent, item)
    }

    function applyNotifyPref(mode, muteUntil) {
        var id = menuChannelId
        if (!id || !app || !app.setChannelNotifyPref)
            return
        app.setChannelNotifyPref(id, mode, { muteUntil: muteUntil || 0 }, function() {})
        menuNotifyMode = Storage.getEffectiveNotifyMode(id)
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

    function syncUnreadFromStorage() {
        if (app && app.refreshConversationUnread && allItems && allItems.length > 0) {
            allItems = app.refreshConversationUnread(allItems)
            applyFilter()
        }
    }

    // PageStack often keeps this page "visible" under ChatPage, so onVisibleChanged
    // may not fire when popping back — watch the stack instead.
    Connections {
        target: pageStack
        onDepthChanged: {
            if (pageStack.currentPage === conversationsPage)
                conversationsPage.syncUnreadFromStorage()
        }
        onCurrentPageChanged: {
            if (pageStack.currentPage === conversationsPage)
                conversationsPage.syncUnreadFromStorage()
        }
    }

    onVisibleChanged: {
        if (!visible)
            return
        conversationsPage.syncUnreadFromStorage()
        if (app && app.pendingConversationsReload) {
            app.pendingConversationsReload = false
            reload()
        }
    }

    Component {
        id: notifyMenuComponent
        Popover {
            id: notifyPopover

            // Plain rows — ListItem dividers stack badly inside Popover.
            Column {
                id: menuColumn
                width: units.gu(30)
                spacing: 0

                function closeWith(mode, muteUntil) {
                    conversationsPage.applyNotifyPref(mode, muteUntil || 0)
                    PopupUtils.close(notifyPopover)
                }

                Item {
                    width: parent.width
                    height: units.gu(4.5)
                    Label {
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: units.gu(2)
                            rightMargin: units.gu(2)
                        }
                        text: i18n.tr("Notify you about…")
                        fontSize: "small"
                        color: theme.palette.normal.backgroundSecondaryText
                    }
                }

                Item {
                    width: parent.width
                    height: units.gu(1.5)
                    Rectangle {
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: units.gu(1)
                            rightMargin: units.gu(1)
                        }
                        height: units.dp(1)
                        color: theme.palette.normal.base
                        opacity: 0.55
                    }
                }

                AbstractButton {
                    width: parent.width
                    height: units.gu(5.5)
                    onClicked: menuColumn.closeWith("all", 0)
                    Icon {
                        id: allIcon
                        anchors {
                            left: parent.left
                            verticalCenter: parent.verticalCenter
                            leftMargin: units.gu(2)
                        }
                        name: "notification"
                        width: units.gu(2.2)
                        height: units.gu(2.2)
                        color: theme.palette.normal.backgroundText
                    }
                    Label {
                        anchors {
                            left: allIcon.right
                            right: allCheck.left
                            verticalCenter: parent.verticalCenter
                            leftMargin: units.gu(1.5)
                            rightMargin: units.gu(1)
                        }
                        text: i18n.tr("All new posts")
                        elide: Text.ElideRight
                        color: theme.palette.normal.backgroundText
                    }
                    Icon {
                        id: allCheck
                        anchors {
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            rightMargin: units.gu(2)
                        }
                        name: "ok"
                        width: units.gu(2)
                        height: units.gu(2)
                        visible: conversationsPage.menuNotifyMode === "all"
                        color: theme.palette.normal.activity
                    }
                }

                AbstractButton {
                    width: parent.width
                    height: units.gu(5.5)
                    onClicked: menuColumn.closeWith("mentions", 0)
                    Icon {
                        id: mentionIcon
                        anchors {
                            left: parent.left
                            verticalCenter: parent.verticalCenter
                            leftMargin: units.gu(2)
                        }
                        name: "contact"
                        width: units.gu(2.2)
                        height: units.gu(2.2)
                        color: theme.palette.normal.backgroundText
                    }
                    Label {
                        anchors {
                            left: mentionIcon.right
                            right: mentionCheck.left
                            verticalCenter: parent.verticalCenter
                            leftMargin: units.gu(1.5)
                            rightMargin: units.gu(1)
                        }
                        text: i18n.tr("Just mentions")
                        elide: Text.ElideRight
                        color: theme.palette.normal.backgroundText
                    }
                    Icon {
                        id: mentionCheck
                        anchors {
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            rightMargin: units.gu(2)
                        }
                        name: "ok"
                        width: units.gu(2)
                        height: units.gu(2)
                        visible: conversationsPage.menuNotifyMode === "mentions"
                        color: theme.palette.normal.activity
                    }
                }

                AbstractButton {
                    width: parent.width
                    height: units.gu(5.5)
                    onClicked: menuColumn.closeWith("mute", 0)
                    Icon {
                        id: muteIcon
                        anchors {
                            left: parent.left
                            verticalCenter: parent.verticalCenter
                            leftMargin: units.gu(2)
                        }
                        name: "notification-silent"
                        width: units.gu(2.2)
                        height: units.gu(2.2)
                        color: theme.palette.normal.backgroundText
                    }
                    Label {
                        anchors {
                            left: muteIcon.right
                            right: muteCheck.left
                            verticalCenter: parent.verticalCenter
                            leftMargin: units.gu(1.5)
                            rightMargin: units.gu(1)
                        }
                        text: i18n.tr("Mute")
                        elide: Text.ElideRight
                        color: theme.palette.normal.backgroundText
                    }
                    Icon {
                        id: muteCheck
                        anchors {
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            rightMargin: units.gu(2)
                        }
                        name: "ok"
                        width: units.gu(2)
                        height: units.gu(2)
                        visible: conversationsPage.menuNotifyMode === "mute"
                        color: theme.palette.normal.activity
                    }
                }

                Item {
                    width: parent.width
                    height: units.gu(1.5)
                    Rectangle {
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: units.gu(1)
                            rightMargin: units.gu(1)
                        }
                        height: units.dp(1)
                        color: theme.palette.normal.base
                        opacity: 0.55
                    }
                }

                Item {
                    width: parent.width
                    height: units.gu(4.5)
                    Label {
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: units.gu(2)
                            rightMargin: units.gu(2)
                        }
                        text: i18n.tr("Temporarily mute…")
                        fontSize: "small"
                        color: theme.palette.normal.backgroundSecondaryText
                    }
                }

                AbstractButton {
                    width: parent.width
                    height: units.gu(5.5)
                    onClicked: menuColumn.closeWith("mute", Storage.muteUntilTomorrowMs())
                    Icon {
                        id: tomorrowIcon
                        anchors {
                            left: parent.left
                            verticalCenter: parent.verticalCenter
                            leftMargin: units.gu(2)
                        }
                        name: "history"
                        width: units.gu(2.2)
                        height: units.gu(2.2)
                        color: theme.palette.normal.backgroundText
                    }
                    Label {
                        anchors {
                            left: tomorrowIcon.right
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: units.gu(1.5)
                            rightMargin: units.gu(2)
                        }
                        text: i18n.tr("Until tomorrow")
                        elide: Text.ElideRight
                        color: theme.palette.normal.backgroundText
                    }
                }

                AbstractButton {
                    width: parent.width
                    height: units.gu(5.5)
                    onClicked: menuColumn.closeWith("mute", Storage.muteUntilOneHourMs())
                    Icon {
                        id: hourIcon
                        anchors {
                            left: parent.left
                            verticalCenter: parent.verticalCenter
                            leftMargin: units.gu(2)
                        }
                        name: "history"
                        width: units.gu(2.2)
                        height: units.gu(2.2)
                        color: theme.palette.normal.backgroundText
                    }
                    Label {
                        anchors {
                            left: hourIcon.right
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: units.gu(1.5)
                            rightMargin: units.gu(2)
                        }
                        text: i18n.tr("1 hour")
                        elide: Text.ElideRight
                        color: theme.palette.normal.backgroundText
                    }
                }
            }
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
                      : (rowType === "seeMore" ? units.gu(8) : units.gu(7))

                SectionHeader {
                    anchors.fill: parent
                    visible: rowType === "header"
                    titleText: title
                    count: count
                    expanded: expanded
                    onToggled: conversationsPage.toggleSection(sectionId)
                }

                ListItem {
                    anchors {
                        fill: parent
                        topMargin: units.gu(1)
                        bottomMargin: units.gu(1)
                    }
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
                    id: convDelegate
                    anchors.fill: parent
                    visible: rowType === "item"
                    titleText: model.title
                    subtitleText: model.subtitle
                    isIm: model.isIm
                    isPrivate: model.isPrivate
                    avatarUrl: model.avatarUrl || ""
                    hasUnread: model.hasUnread
                    isHidden: model.isHidden
                    onClicked: {
                        pageStack.push(Qt.resolvedUrl("ChatPage.qml"), {
                            app: conversationsPage.app,
                            channelId: model.convId,
                            channelTitle: model.title
                        })
                    }
                    onHideRequested: conversationsPage.hideConversation(model.convId)
                    onUnhideRequested: conversationsPage.unhideConversation(model.convId)
                    onNotifyPrefsRequested: conversationsPage.openNotifyMenu(convDelegate, model.convId)
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
