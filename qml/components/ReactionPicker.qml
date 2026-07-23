import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import "../js/Models.js" as Models

Dialog {
    id: root
    title: i18n.tr("Add reaction")

    property var app: null
    property var commonNames: []
    property var customNames: []

    signal picked(string name)

    Component.onCompleted: {
        commonNames = (app && app.commonReactions) ? app.commonReactions() : Models.commonReactionNames()
        if (app && app.loadCustomEmoji) {
            app.loadCustomEmoji(function() {
                customNames = app.customEmojiNames() || []
            })
        } else {
            customNames = []
        }
    }

    function displayFor(name) {
        if (app && app.reactionDisplay)
            return app.reactionDisplay(name)
        return Models.reactionDisplay(name)
    }

    Column {
        width: parent.width
        spacing: units.gu(1)

        Label {
            width: parent.width
            text: i18n.tr("Common")
            fontSize: "small"
            font.bold: true
            color: theme.palette.normal.backgroundSecondaryText
        }

        Flow {
            width: parent.width
            spacing: units.gu(0.75)

            Repeater {
                model: root.commonNames
                delegate: AbstractButton {
                    width: units.gu(5)
                    height: units.gu(5)
                    onClicked: {
                        root.picked(modelData)
                        PopupUtils.close(root)
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: units.gu(0.75)
                        color: theme.palette.normal.foreground
                        border.color: theme.palette.normal.base
                        border.width: units.dp(1)
                    }

                    Label {
                        anchors.centerIn: parent
                        text: {
                            var d = root.displayFor(modelData)
                            return (d && d.glyph) ? d.glyph : (":" + modelData + ":")
                        }
                        fontSize: "large"
                    }
                }
            }
        }

        Label {
            width: parent.width
            visible: root.customNames.length > 0
            text: i18n.tr("Custom")
            fontSize: "small"
            font.bold: true
            color: theme.palette.normal.backgroundSecondaryText
        }

        Flow {
            width: parent.width
            spacing: units.gu(0.75)
            visible: root.customNames.length > 0

            Repeater {
                model: root.customNames
                delegate: AbstractButton {
                    width: units.gu(5)
                    height: units.gu(5)
                    onClicked: {
                        root.picked(modelData)
                        PopupUtils.close(root)
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: units.gu(0.75)
                        color: theme.palette.normal.foreground
                        border.color: theme.palette.normal.base
                        border.width: units.dp(1)
                    }

                    Image {
                        anchors.centerIn: parent
                        width: units.gu(3)
                        height: units.gu(3)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        source: {
                            var d = root.displayFor(modelData)
                            return (d && d.url) ? d.url : ""
                        }
                    }
                }
            }
        }

        Button {
            width: parent.width
            text: i18n.tr("Cancel")
            onClicked: PopupUtils.close(root)
        }
    }
}
