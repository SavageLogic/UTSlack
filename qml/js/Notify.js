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
// When true (relay mode), skip sendPush — relay owns notifications.
var _appSendsPush = true

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

function setAppSendsPush(enabled) {
    _appSendsPush = !!enabled
}

function appSendsPush() {
    return _appSendsPush
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

function conversationMeta(channelId) {
    return _conversationMeta[channelId] || {}
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

function pushTagFor(channelId, ts) {
    if (channelId && ts)
        return channelId + ":" + ts
    return channelId || "utslack"
}

function deepLinkForMessage(messageObj) {
    var channelId = (messageObj && messageObj.channelId) || ""
    if (!channelId)
        return "appid://utslack.savagelogic/utslack/current-user-version"
    var url = "utslack://open?channel=" + encodeURIComponent(channelId)
    var title = (messageObj && messageObj.channelTitle) || ""
    if (title)
        url += "&title=" + encodeURIComponent(title)
    return url
}

function sendPush(summary, body, tag, messageObj) {
    if (!_pushToken) {
        console.log("[notify] no push token yet")
        return false
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
                    // Deep-link into the conversation; url-dispatcher launches/resumes the app.
                    actions: [deepLinkForMessage(messageObj)]
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
        else
            console.log("[notify] push ok", xhr.status)
    }
    xhr.send(JSON.stringify(payload))
    return true
}

function _firstConversation(wantDm) {
    var cached = Storage.getConversationsCache(null)
    var items = (cached && cached.items) ? cached.items : []
    for (var i = 0; i < items.length; i++) {
        var it = items[i]
        if (!it || !it.id)
            continue
        var isDm = !!(it.isIm || it.isMpim)
        if (wantDm && isDm)
            return it
        if (!wantDm && !isDm)
            return it
    }
    return null
}

// Dev/test helper: fire a sample notification for a DM or channel.
// kind: "dm" | "channel"
// Returns { ok: bool, message: string }
function sendTestNotification(kind) {
    if (!_pushToken)
        return { ok: false, message: "No push token yet" }
    var wantDm = (kind === "dm")
    var found = _firstConversation(wantDm)
    if (!found)
        return {
            ok: false,
            message: wantDm ? "No DM in conversations list" : "No channel in conversations list"
        }
    var channelId = found.id
    var title = found.title || found.name || channelId
    var body = wantDm
        ? "Test DM notification from UTSlack"
        : "Someone: Test channel notification from UTSlack"
    var ts = "" + (Date.now() / 1000)
    var ok = sendPush(title, body, pushTagFor(channelId, ts), {
        channelId: channelId,
        channelTitle: title,
        ts: ts,
        test: true
    })
    if (!ok)
        return { ok: false, message: "Push send failed" }
    return { ok: true, message: "Sent to “" + title + "”" }
}

function _messageMentionsSelf(msg) {
    return Models.messageMentionsUser(msg, _selfUserId)
}

function _looksLikeIm(channelId) {
    // Slack IM ids are D… (public C…, private/mpim often G…)
    return !!(channelId && ("" + channelId).charAt(0) === "D")
}

function _shouldNotify(channelId, msg) {
    var mode = Storage.getEffectiveNotifyMode(channelId)
    if (mode === "mute")
        return false
    if (mode === "mentions") {
        var meta = _conversationMeta[channelId] || {}
        // 1:1 DMs are always "for you" (meta may be missing if not in watch list)
        if ((meta.isIm && !meta.isMpim) || _looksLikeIm(channelId))
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
    var asIm = (meta && meta.isIm && !meta.isMpim) || _looksLikeIm(channelId)
    var body = asIm ? text : (author + ": " + text)
    var tag = pushTagFor(channelId, msg.ts || "")
    sendPush(title, body, tag, {
        channelId: channelId,
        channelTitle: title,
        ts: msg.ts || ""
    })
    if (msg.ts)
        markSeen(channelId, msg.ts)
}

// Shared by poller and Socket Mode. sendPushOnly applies mute/prefs;
// when _appSendsPush is false (relay mode), only advances lastSeenMap.
function handleIncomingMessage(channelId, msg, options) {
    options = options || {}
    if (!channelId || !msg)
        return false
    var cached = _conversationMeta[channelId] || {}
    var meta = {
        title: cached.title || options.channelTitle || channelId,
        isIm: !!(cached.isIm || options.isIm || _looksLikeIm(channelId)),
        isMpim: !!(cached.isMpim || options.isMpim)
    }
    var map = Storage.getLastSeenMap()
    var oldest = map[channelId] || "0"
    if (msg.ts && msg.ts <= oldest) {
        console.log("[notify] skip already-seen", channelId, msg.ts, "<=", oldest)
        return false
    }

    if (!_enabled) {
        if (msg.ts)
            markSeen(channelId, msg.ts)
        return false
    }

    if (_selfUserId && msg.userId === _selfUserId) {
        if (msg.ts)
            markSeen(channelId, msg.ts)
        return false
    }

    if (_appSendsPush && _shouldNotify(channelId, msg)) {
        console.log("[notify] push", channelId, "im=" + meta.isIm, "ts=" + (msg.ts || ""))
        _notifyMessage(channelId, meta, msg)
        return true
    }

    if (msg.ts)
        markSeen(channelId, msg.ts)
    return false
}

function pollOnce(callback) {
    if (!_enabled || _busy || !_pushToken || _conversationIds.length === 0) {
        if (callback)
            callback(false)
        return
    }
    // In relay mode the relay owns pushes; skip notify polling.
    if (!_appSendsPush) {
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
