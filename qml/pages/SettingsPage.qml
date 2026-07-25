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

    Component {
        id: logoutDialog
        Dialog {
            id: dialogue
            title: i18n.tr("Log out?")
            text: i18n.tr("This removes the saved token from this device.")
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
