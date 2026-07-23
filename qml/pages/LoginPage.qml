import QtQuick 2.7
import Lomiri.Components 1.3

Page {
    id: loginPage

    property var app
    property bool busy: false
    property string errorText: ""

    // Hidden helper: Qt.labs.platform Clipboard is unavailable on UT;
    // TextEdit.paste() still reads the system clipboard.
    TextEdit {
        id: pasteHelper
        visible: false
        width: 0
        height: 0
        text: ""
    }

    function pasteTokenFromClipboard() {
        pasteHelper.text = ""
        pasteHelper.paste()
        var pasted = ("" + pasteHelper.text).trim()
        if (pasted.length > 0)
            tokenField.text = pasted
        else
            loginPage.errorText = i18n.tr("Clipboard is empty — copy the token in the browser first, then tap Paste.")
    }

    header: PageHeader {
        id: header
        title: i18n.tr("Connect to Slack")
    }

    Flickable {
        id: flick
        anchors {
            fill: parent
            topMargin: header.height
        }
        contentHeight: contentCol.height + units.gu(4)
        clip: true

        Column {
            id: contentCol
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: units.gu(2)
            }
            spacing: units.gu(2)

            Rectangle {
                width: parent.width
                height: units.gu(12)
                radius: units.gu(1)
                color: "#4A154B"

                Column {
                    anchors.centerIn: parent
                    spacing: units.gu(0.5)

                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "UTSlack"
                        color: "white"
                        font.pixelSize: units.gu(3.5)
                        font.bold: true
                    }
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: i18n.tr("Native Slack for Ubuntu Touch")
                        color: "#F5E9F7"
                        fontSize: "small"
                    }
                }
            }

            Label {
                width: parent.width
                wrapMode: Text.Wrap
                text: i18n.tr("Paste a Slack User OAuth Token (xoxp-…). Create a Slack app with user token scopes — see the README for the full list.")
                color: theme.palette.normal.backgroundSecondaryText
            }

            Label {
                text: i18n.tr("User OAuth Token (xoxp-…)")
                font.bold: true
            }

            TextField {
                id: tokenField
                width: parent.width
                placeholderText: i18n.tr("xoxp-…")
                enabled: !loginPage.busy
                // Tokens are secrets; avoid OSK autocorrect / prediction
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhSensitiveData
            }

            Button {
                width: parent.width
                text: i18n.tr("Paste from clipboard")
                enabled: !loginPage.busy
                onClicked: {
                    loginPage.errorText = ""
                    loginPage.pasteTokenFromClipboard()
                }
            }

            Label {
                width: parent.width
                wrapMode: Text.Wrap
                fontSize: "small"
                color: theme.palette.normal.backgroundSecondaryText
                text: i18n.tr("Slack app → OAuth & Permissions → Install to Workspace → copy User OAuth Token (not Bot User OAuth Token). Scopes must be under User Token Scopes. If long-press Paste is greyed out, use the button above.")
            }

            Label {
                id: errorLabel
                width: parent.width
                visible: loginPage.errorText.length > 0
                wrapMode: Text.Wrap
                color: theme.palette.normal.negative
                text: loginPage.errorText
            }

            Button {
                id: connectButton
                width: parent.width
                text: loginPage.busy ? i18n.tr("Connecting…") : i18n.tr("Connect")
                color: theme.palette.normal.positive
                enabled: !loginPage.busy && tokenField.text.trim().length > 0
                onClicked: {
                    loginPage.errorText = ""
                    loginPage.busy = true
                    app.connectWithToken(tokenField.text.trim(), function(ok, message) {
                        loginPage.busy = false
                        if (!ok)
                            loginPage.errorText = message || i18n.tr("Connection failed")
                    })
                }
            }

            ActivityIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: loginPage.busy
                visible: running
            }

            Label {
                width: parent.width
                wrapMode: Text.Wrap
                fontSize: "small"
                color: theme.palette.normal.backgroundTertiaryText
                text: i18n.tr("Required user scopes: channels/groups/im/mpim read+history, users:read, chat:write, search:read, files:read/write")
            }
        }
    }
}
