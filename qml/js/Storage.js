.pragma library
.import QtQuick.LocalStorage 2.0 as Sql

var DB_NAME = "utslack"
var DB_VERSION = "1.0"
var DB_DESC = "UTSlack settings"
var DB_SIZE = 100000

function _db() {
    return Sql.LocalStorage.openDatabaseSync(DB_NAME, DB_VERSION, DB_DESC, DB_SIZE)
}

function _ensure() {
    _db().transaction(function(tx) {
        tx.executeSql("CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT)")
    })
}

function get(key, fallback) {
    _ensure()
    var value = fallback
    _db().readTransaction(function(tx) {
        var rs = tx.executeSql("SELECT value FROM settings WHERE key = ?", [key])
        if (rs.rows.length > 0)
            value = rs.rows.item(0).value
    })
    return value
}

function set(key, value) {
    _ensure()
    _db().transaction(function(tx) {
        tx.executeSql(
            "INSERT OR REPLACE INTO settings(key, value) VALUES(?, ?)",
            [key, value === undefined || value === null ? "" : ("" + value)]
        )
    })
}

function getToken() {
    return get("token", "") || ""
}

function setToken(token) {
    set("token", token || "")
}

function clearToken() {
    setToken("")
}

function getNotificationsEnabled() {
    var v = get("notificationsEnabled", "1")
    return v !== "0" && v !== "false"
}

function setNotificationsEnabled(enabled) {
    set("notificationsEnabled", enabled ? "1" : "0")
}

function getLastSeenMap() {
    var raw = get("lastSeenMap", "{}")
    try {
        return JSON.parse(raw || "{}") || {}
    } catch (e) {
        return {}
    }
}

function setLastSeenMap(map) {
    try {
        set("lastSeenMap", JSON.stringify(map || {}))
    } catch (e) {
    }
}

function markChannelSeen(channelId, ts) {
    if (!channelId)
        return
    var map = getLastSeenMap()
    var prev = map[channelId] || "0"
    if (!ts || ts > prev)
        map[channelId] = ts || prev
    setLastSeenMap(map)
}

// Last time the user opened a conversation (for unread bold in the list).
// Kept separate from lastSeenMap so push polling can advance "seen for notify"
// without clearing unread until the chat is actually opened.
// V3: unread = activity newer than last open/seed (not "never opened = unread").
function getLastOpenedMap() {
    var raw = get("lastOpenedMapV3", "")
    if (!raw || raw.length === 0)
        return {}
    try {
        return JSON.parse(raw || "{}") || {}
    } catch (e) {
        return {}
    }
}

function setLastOpenedMap(map) {
    try {
        set("lastOpenedMapV3", JSON.stringify(map || {}))
    } catch (e) {
    }
}

function markChannelOpened(channelId, ts) {
    if (!channelId)
        return
    var map = getLastOpenedMap()
    var prev = parseFloat(map[channelId]) || 0
    var next = ts ? parseFloat(ts) : 0
    if (!next || isNaN(next))
        next = Date.now() / 1000
    // Always advance at least to "now" so channel.updated stamps can't leave us stuck unread
    var stamp = Math.max(prev, next, Date.now() / 1000)
    map[channelId] = "" + stamp
    setLastOpenedMap(map)
}

// Manually hidden conversations (swipe → Hide); shown under See More.
function getHiddenMap() {
    var raw = get("hiddenConversations", "{}")
    try {
        return JSON.parse(raw || "{}") || {}
    } catch (e) {
        return {}
    }
}

function setHiddenMap(map) {
    try {
        set("hiddenConversations", JSON.stringify(map || {}))
    } catch (e) {
    }
}

function isConversationHidden(channelId) {
    if (!channelId)
        return false
    return !!getHiddenMap()[channelId]
}

function setConversationHidden(channelId, hidden) {
    if (!channelId)
        return
    var map = getHiddenMap()
    if (hidden)
        map[channelId] = true
    else
        delete map[channelId]
    setHiddenMap(map)
}

// Per-conversation notification prefs for UTSlack push.
// mode: "all" | "mentions" | "mute"
// muteUntil: epoch ms; >0 means temporary mute that expires.
function getChannelNotifyPrefs() {
    var raw = get("channelNotifyPrefs", "{}")
    try {
        return JSON.parse(raw || "{}") || {}
    } catch (e) {
        return {}
    }
}

function setChannelNotifyPrefs(map) {
    try {
        set("channelNotifyPrefs", JSON.stringify(map || {}))
    } catch (e) {
    }
}

function setChannelNotifyPref(channelId, mode, muteUntil) {
    if (!channelId)
        return
    var map = getChannelNotifyPrefs()
    var m = mode || "all"
    if (m !== "all" && m !== "mentions" && m !== "mute")
        m = "all"
    var until = muteUntil ? Number(muteUntil) : 0
    if (m === "all" && !until) {
        delete map[channelId]
    } else {
        map[channelId] = {
            mode: m,
            muteUntil: until > 0 ? until : 0
        }
    }
    setChannelNotifyPrefs(map)
}

function getEffectiveNotifyMode(channelId) {
    if (!channelId)
        return "all"
    var map = getChannelNotifyPrefs()
    var p = map[channelId]
    if (!p)
        return "all"
    var mode = p.mode || "all"
    var until = Number(p.muteUntil) || 0
    if (mode === "mute") {
        if (until > 0 && until <= Date.now())
            return "all"
        return "mute"
    }
    return mode
}

function muteUntilTomorrowMs() {
    var d = new Date()
    d.setDate(d.getDate() + 1)
    d.setHours(0, 0, 0, 0)
    return d.getTime()
}

function muteUntilOneHourMs() {
    return Date.now() + (60 * 60 * 1000)
}
