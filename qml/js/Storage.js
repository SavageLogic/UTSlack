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
function getLastOpenedMap() {
    var raw = get("lastOpenedMap", "{}")
    try {
        return JSON.parse(raw || "{}") || {}
    } catch (e) {
        return {}
    }
}

function setLastOpenedMap(map) {
    try {
        set("lastOpenedMap", JSON.stringify(map || {}))
    } catch (e) {
    }
}

function markChannelOpened(channelId, ts) {
    if (!channelId)
        return
    var map = getLastOpenedMap()
    var prev = map[channelId] || "0"
    var next = ts ? ("" + ts) : prev
    if (!next)
        return
    if (parseFloat(next) >= parseFloat(prev || "0"))
        map[channelId] = next
    setLastOpenedMap(map)
}
