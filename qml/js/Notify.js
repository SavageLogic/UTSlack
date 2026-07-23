.pragma library
.import "SlackClient.js" as Slack
.import "Models.js" as Models
.import "Storage.js" as Storage

var APP_PUSH_ID = "utslack.savagelogic_utslack"
var POLL_LIMIT = 12
var HISTORY_LIMIT = 5

var _pushToken = ""
var _selfUserId = ""
var _enabled = true
var _busy = false
var _conversationIds = []
var _conversationMeta = {}

function setPushToken(token) {
    _pushToken = token || ""
}

function getPushToken() {
    return _pushToken
}

function setSelfUserId(userId) {
    _selfUserId = userId || ""
}

function setEnabled(enabled) {
    _enabled = !!enabled
    Storage.setNotificationsEnabled(_enabled)
}

function isEnabled() {
    return _enabled
}

function loadPrefs() {
    _enabled = Storage.getNotificationsEnabled()
}

function setConversations(items) {
    _conversationIds = []
    _conversationMeta = {}
    if (!items)
        return
    for (var i = 0; i < items.length; i++) {
        var it = items[i]
        if (!it || !it.id)
            continue
        _conversationIds.push(it.id)
        _conversationMeta[it.id] = {
            title: it.title || it.name || it.id,
            isIm: !!(it.isIm || it.isMpim),
            isMpim: !!it.isMpim
        }
    }
}

function initializeSeenBaselines() {
    var map = Storage.getLastSeenMap()
    var now = "" + (Date.now() / 1000)
    var changed = false
    for (var i = 0; i < _conversationIds.length; i++) {
        var id = _conversationIds[i]
        if (!map[id]) {
            map[id] = now
            changed = true
        }
    }
    if (changed)
        Storage.setLastSeenMap(map)
}

function markSeen(channelId, ts) {
    Storage.markChannelSeen(channelId, ts)
}

function sendPush(summary, body, tag, messageObj) {
    if (!_pushToken) {
        console.log("[notify] no push token yet")
        return
    }
    var expire = new Date()
    expire.setUTCMinutes(expire.getUTCMinutes() + 30)
    var payload = {
        appid: APP_PUSH_ID,
        expire_on: expire.toISOString(),
        token: _pushToken,
        data: {
            notification: {
                tag: tag || "utslack",
                card: {
                    summary: summary || "UTSlack",
                    body: body || "",
                    popup: true,
                    persist: true,
                    actions: ["appid://utslack.savagelogic/utslack/current-user-version"]
                },
                sound: true,
                vibrate: true
            },
            message: messageObj || {}
        }
    }

    var xhr = new XMLHttpRequest()
    xhr.open("POST", "https://push.ubports.com/notify")
    xhr.setRequestHeader("Content-Type", "application/json")
    xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE)
            return
        if (xhr.status < 200 || xhr.status >= 300)
            console.log("[notify] push failed", xhr.status, xhr.responseText)
    }
    xhr.send(JSON.stringify(payload))
}

function _messageMentionsSelf(msg) {
    return Models.messageMentionsUser(msg, _selfUserId)
}

function _shouldNotify(channelId, msg) {
    var mode = Storage.getEffectiveNotifyMode(channelId)
    if (mode === "mute")
        return false
    if (mode === "mentions") {
        var meta = _conversationMeta[channelId] || {}
        // 1:1 DMs are always "for you"
        if (meta.isIm && !meta.isMpim)
            return true
        return _messageMentionsSelf(msg)
    }
    return true
}

function _notifyMessage(channelId, meta, msg) {
    if (!msg)
        return
    if (_selfUserId && msg.userId === _selfUserId)
        return
    var title = (meta && meta.title) ? meta.title : "Slack"
    var author = msg.author || "Someone"
    var text = msg.plainText || msg.text || ""
    // Notifications should stay plain — strip any leftover tags
    text = text.replace(/<[^>]+>/g, "")
    if (text.length > 120)
        text = text.substring(0, 117) + "…"
    var body = meta && meta.isIm ? text : (author + ": " + text)
    sendPush(title, body, channelId, {
        channelId: channelId,
        channelTitle: title,
        ts: msg.ts || ""
    })
    if (msg.ts)
        markSeen(channelId, msg.ts)
}

function pollOnce(callback) {
    if (!_enabled || _busy || !_pushToken || _conversationIds.length === 0) {
        if (callback)
            callback(false)
        return
    }
    _busy = true
    var map = Storage.getLastSeenMap()
    var ids = _conversationIds.slice(0, POLL_LIMIT)
    var index = 0
    var notified = 0

    function next() {
        if (index >= ids.length) {
            _busy = false
            if (callback)
                callback(true, notified)
            return
        }
        var channelId = ids[index++]
        var oldest = map[channelId]
        var opts = { limit: HISTORY_LIMIT }
        if (oldest)
            opts.oldest = oldest

        Slack.conversationsHistory(channelId, opts, function(res) {
            if (res && res.ok) {
                var items = Models.normalizeMessages(res.messages || [])
                var meta = _conversationMeta[channelId] || {}
                var newest = oldest || "0"
                var latestFresh = null
                for (var i = 0; i < items.length; i++) {
                    var m = items[i]
                    if (!m.ts || (oldest && m.ts <= oldest))
                        continue
                    if (m.ts > newest)
                        newest = m.ts
                    // Keep the newest inbound message for a single notification
                    if (!_selfUserId || m.userId !== _selfUserId) {
                        if (!latestFresh || m.ts > latestFresh.ts)
                            latestFresh = m
                    }
                }
                if (latestFresh && _shouldNotify(channelId, latestFresh)) {
                    _notifyMessage(channelId, meta, latestFresh)
                    notified++
                } else if (newest && newest !== oldest) {
                    markSeen(channelId, newest)
                }
            }
            next()
        })
    }

    next()
}
