import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import "../js/Notify.js" as Notify

Page {
    id: settingsPage

    property var app
    property int notifLabelTaps: 0
    property bool showNotifyDebug: false
    property string notifyDebugStatus: ""

    header: PageHeader {
        id: header
        title: i18n.tr("Settings")
    }

    function tapNotificationsLabel() {
        if (showNotifyDebug)
            return
        notifLabelTaps++
        if (notifLabelTaps >= 7)
            showNotifyDebug = true
    }

    function sendTest(kind) {
        var res = Notify.sendTestNotification(kind)
        notifyDebugStatus = (res && res.message) ? res.message : i18n.tr("Failed")
        if (app)
            app.pushStatus = notifyDebugStatus
    }

    Flickable {
        anchors {
            fill: parent
            topMargin: header.height
        }
        contentHeight: column.height + units.gu(4)
        clip: true

        Column {
            id: column
            anchors {
                left: parent.left
                right: parent.right
                margins: units.gu(2)
            }
            spacing: units.gu(2)

            Item { width: 1; height: units.gu(1) }

            Label {
                text: i18n.tr("Workspace")
                font.bold: true
            }
            Label {
                width: parent.width
                wrapMode: Text.Wrap
                text: (app && app.teamName) ? app.teamName : i18n.tr("Unknown")
            }

            Label {
                text: i18n.tr("Signed in as")
                font.bold: true
            }
            Label {
                width: parent.width
                wrapMode: Text.Wrap
                text: (app && app.userName) ? app.userName : i18n.tr("Unknown")
            }

            Rectangle {
                width: parent.width
                height: units.dp(1)
                color: theme.palette.normal.base
            }

            // Tap this label 7× to unlock notification test controls
            Label {
                text: i18n.tr("Notifications")
                font.bold: true

                MouseArea {
                    anchors.fill: parent
                    onClicked: settingsPage.tapNotificationsLabel()
                }
            }

            ListItem {
                height: notifLayout.height + (divider.visible ? divider.height : 0)
                ListItemLayout {
                    id: notifLayout
                    title.text: i18n.tr("Message notifications")
                    subtitle.text: i18n.tr("Alert for new messages while UTSlack is running")
                    Switch {
                        id: notifSwitch
                        checked: app ? app.notificationsEnabled : true
                        SlotsLayout.position: SlotsLayout.Trailing
                        onCheckedChanged: {
                            if (app && checked !== app.notificationsEnabled)
                                app.setNotificationsEnabled(checked)
                        }
                    }
                }
            }

            Label {
                width: parent.width
                wrapMode: Text.Wrap
                fontSize: "small"
                color: theme.palette.normal.backgroundSecondaryText
                text: (app && app.pushStatus)
                      ? app.pushStatus
                      : i18n.tr("Requires an OpenStore / UBports account on this device. Notifications work while the app is open or kept alive in the background.")
            }

            Column {
                width: parent.width
                spacing: units.gu(2)
                visible: notifSwitch.checked

                Label {
                    text: i18n.tr("Realtime source")
                    font.bold: true
                }

                Label {
                    width: parent.width
                    wrapMode: Text.Wrap
                    fontSize: "small"
                    color: theme.palette.normal.backgroundSecondaryText
                    text: i18n.tr("Choose in-app Slack Socket Mode, or an external relay over SSE. Only one should own Slack events.")
                }

                OptionSelector {
                    id: realtimeModeSelector
                    width: parent.width
                    text: i18n.tr("Updates & notifications")
                    model: [
                        i18n.tr("In-app (Slack Socket Mode)"),
                        i18n.tr("External relay (SSE)")
                    ]
                    containerHeight: itemHeight * 2
                    Component.onCompleted: {
                        selectedIndex = (app && app.realtimeMode === "relay") ? 1 : 0
                    }
                    onSelectedIndexChanged: {
                        if (!app || !app.setRealtimeMode)
                            return
                        var mode = selectedIndex === 1 ? "relay" : "socket"
                        if (mode !== app.realtimeMode)
                            app.setRealtimeMode(mode)
                    }
                }

                Label {
                    width: parent.width
                    wrapMode: Text.Wrap
                    fontSize: "small"
                    color: theme.palette.normal.backgroundSecondaryText
                    text: (app && app.realtimeStatus) ? app.realtimeStatus : ""
                    visible: text.length > 0
                }

                Column {
                    width: parent.width
                    spacing: units.gu(1)
                    visible: realtimeModeSelector.selectedIndex === 0

                    Label {
                        text: i18n.tr("App-level token")
                        font.bold: true
                    }
                    Label {
                        width: parent.width
                        wrapMode: Text.Wrap
                        fontSize: "small"
                        color: theme.palette.normal.backgroundSecondaryText
                        text: i18n.tr("From api.slack.com → your app → Basic Information → App-Level Tokens (xapp-… with connections:write). Enable Socket Mode and Event Subscriptions for messages.")
                    }
                    TextField {
                        id: appTokenField
                        width: parent.width
                        echoMode: TextInput.Password
                        placeholderText: i18n.tr("xapp-…")
                        text: app ? (app.appToken || "") : ""
                    }
                    Button {
                        width: parent.width
                        text: i18n.tr("Save app token")
                        onClicked: {
                            if (!app || !app.setAppToken)
                                return
                            app.setAppToken(appTokenField.text.trim())
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: units.gu(1)
                    visible: realtimeModeSelector.selectedIndex === 1

                    Label {
                        text: i18n.tr("Relay SSE URL")
                        font.bold: true
                    }
                    Label {
                        width: parent.width
                        wrapMode: Text.Wrap
                        fontSize: "small"
                        color: theme.palette.normal.backgroundSecondaryText
                        text: i18n.tr("Must be reachable from this device (VPS, Tailscale, or tunnel). The relay owns Slack events and UBports pushes; the app only streams UI updates over SSE.")
                    }
                    TextField {
                        id: relayUrlField
                        width: parent.width
                        placeholderText: i18n.tr("https://relay.example.com/events")
                        inputMethodHints: Qt.ImhUrlCharactersOnly
                        text: app ? (app.relaySseUrl || "") : ""
                    }
                    Button {
                        width: parent.width
                        text: i18n.tr("Save relay URL")
                        onClicked: {
                            if (!app || !app.setRelaySseUrl)
                                return
                            app.setRelaySseUrl(relayUrlField.text.trim())
                        }
                    }
                }

                Label {
                    text: i18n.tr("Polling fallback")
                    font.bold: true
                }

                Label {
                    width: parent.width
                    wrapMode: Text.Wrap
                    fontSize: "small"
                    color: theme.palette.normal.backgroundSecondaryText
                    text: i18n.tr("Used when the live connection is down. Shorter intervals feel snappier but use more battery and API calls.")
                }

                OptionSelector {
                    id: chatPollSelector
                    width: parent.width
                    text: i18n.tr("Open chat / thread")
                    model: [
                        i18n.tr("5 seconds"),
                        i18n.tr("8 seconds (default)"),
                        i18n.tr("15 seconds"),
                        i18n.tr("30 seconds"),
                        i18n.tr("60 seconds")
                    ]
                    containerHeight: itemHeight * 4
                    Component.onCompleted: selectedIndex = settingsPage.indexForChatPoll()
                    onSelectedIndexChanged: {
                        if (!app || !app.setChatPollSeconds)
                            return
                        var secs = settingsPage.chatPollSecondsForIndex(selectedIndex)
                        if (secs !== app.chatPollSeconds)
                            app.setChatPollSeconds(secs)
                    }
                }

                OptionSelector {
                    id: notifyPollSelector
                    width: parent.width
                    text: i18n.tr("Channels & DMs (notifications)")
                    model: [
                        i18n.tr("15 seconds"),
                        i18n.tr("30 seconds"),
                        i18n.tr("45 seconds (default)"),
                        i18n.tr("60 seconds"),
                        i18n.tr("2 minutes"),
                        i18n.tr("5 minutes"),
                        i18n.tr("15 minutes"),
                        i18n.tr("30 minutes"),
                        i18n.tr("1 hour")
                    ]
                    containerHeight: itemHeight * 4
                    Component.onCompleted: selectedIndex = settingsPage.indexForNotifyPoll()
                    onSelectedIndexChanged: {
                        if (!app || !app.setNotifyPollSeconds)
                            return
                        var secs = settingsPage.notifyPollSecondsForIndex(selectedIndex)
                        if (secs !== app.notifyPollSeconds)
                            app.setNotifyPollSeconds(secs)
                    }
                }
            }

            Column {
                width: parent.width
                spacing: units.gu(1)
                visible: settingsPage.showNotifyDebug

                Rectangle {
                    width: parent.width
                    height: units.dp(1)
                    color: theme.palette.normal.base
                }

                Label {
                    text: i18n.tr("Notification testing")
                    font.bold: true
                }

                Label {
                    width: parent.width
                    wrapMode: Text.Wrap
                    fontSize: "small"
                    color: theme.palette.normal.backgroundSecondaryText
                    text: i18n.tr("Sends a real push using your device token. Uses the first DM / channel in your conversations list.")
                }

                Button {
                    width: parent.width
                    text: i18n.tr("Send test DM notification")
                    onClicked: settingsPage.sendTest("dm")
                }

                Button {
                    width: parent.width
                    text: i18n.tr("Send test channel notification")
                    onClicked: settingsPage.sendTest("channel")
                }

                Label {
                    width: parent.width
                    wrapMode: Text.Wrap
                    fontSize: "small"
                    visible: settingsPage.notifyDebugStatus.length > 0
                    color: theme.palette.normal.backgroundSecondaryText
                    text: settingsPage.notifyDebugStatus
                }
            }

            Rectangle {
                width: parent.width
                height: units.dp(1)
                color: theme.palette.normal.base
            }

            Button {
                width: parent.width
                text: i18n.tr("Log out")
                color: theme.palette.normal.negative
                onClicked: PopupUtils.open(logoutDialog)
            }

            Label {
                width: parent.width
                wrapMode: Text.Wrap
                fontSize: "small"
                color: theme.palette.normal.backgroundSecondaryText
                text: i18n.tr("UTSlack v1.0.0 — native Slack client for Ubuntu Touch.")
            }
        }
    }

    readonly property var chatPollChoices: [5, 8, 15, 30, 60]
    readonly property var notifyPollChoices: [15, 30, 45, 60, 120, 300, 900, 1800, 3600]

    function chatPollSecondsForIndex(index) {
        var list = chatPollChoices
        if (index < 0 || index >= list.length)
            return 8
        return list[index]
    }

    function indexForChatPoll() {
        var secs = app ? app.chatPollSeconds : 8
        var list = chatPollChoices
        for (var i = 0; i < list.length; i++) {
            if (list[i] === secs)
                return i
        }
        return 1
    }

    function notifyPollSecondsForIndex(index) {
        var list = notifyPollChoices
        if (index < 0 || index >= list.length)
            return 45
        return list[index]
    }

    function indexForNotifyPoll() {
        var secs = app ? app.notifyPollSeconds : 45
        var list = notifyPollChoices
        for (var i = 0; i < list.length; i++) {
            if (list[i] === secs)
                return i
        }
        return 2
    }

    Component {
        id: logoutDialog
        Dialog {
            id: dialogue
            title: i18n.tr("Log out?")
            text: i18n.tr("This removes the saved user token and app-level token from this device.")
            Button {
                text: i18n.tr("Log out")
                color: theme.palette.normal.negative
                onClicked: {
                    PopupUtils.close(dialogue)
                    app.logout()
                }
            }
            Button {
                text: i18n.tr("Cancel")
                onClicked: PopupUtils.close(dialogue)
            }
        }
    }
}
