import QtQuick 2.7
import Lomiri.Components 1.3

// Adaptive colors for light (Ambiance) and dark (SuruDark) system themes.
// Instantiate under MainView (or any StyledItem) so `theme` is in scope.
Item {
    id: root
    width: 0
    height: 0
    visible: false

    readonly property bool dark: {
        var n = "" + (theme && theme.name ? theme.name : "")
        return n.indexOf("SuruDark") !== -1
    }

    // Slack brand (intentional; works as accent on both themes)
    readonly property color brand: "#4A154B"
    readonly property color brandMuted: dark ? "#C9A0CE" : "#611f69"
    readonly property color brandHeroText: "#F5E9F7"

    readonly property color accentDm: dark ? "#5BC8EB" : "#36C5F0"
    readonly property color accentChannel: brand

    readonly property color positive: theme.palette.normal.positive
    readonly property color negative: theme.palette.normal.negative
    readonly property color activity: theme.palette.normal.activity
    // Readable link accent on dark bubbles (SuruDark activity is too dark)
    readonly property color link: dark ? "#7EB6FF" : theme.palette.normal.activity

    readonly property color bubbleSelf: dark ? "#1B3D2F" : "#E8F5E9"
    readonly property color bubbleSelfBorder: dark ? "#2D6A4F" : "#C8E6C9"
    readonly property color bubbleOther: theme.palette.normal.foreground
    readonly property color bubbleOtherBorder: theme.palette.normal.base
    readonly property color bubbleText: theme.palette.normal.foregroundText
    readonly property color author: dark ? brandMuted : brand
    readonly property color brandForeground: "#FFFFFF"
}
