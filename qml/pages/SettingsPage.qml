import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3

Page {
    id: settingsPage

    property var app

    header: PageHeader {
        id: header
        title: i18n.tr("Settings")
    }

    Column {
        anchors {
            fill: parent
            margins: units.gu(2)
        }
        spacing: units.gu(2)

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

        Label {
            text: i18n.tr("Notifications")
            font.bold: true
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
