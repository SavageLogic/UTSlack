.pragma library

var API_BASE = "https://slack.com/api/"
var _token = ""
var _userCache = {}
var _authInfo = null
var _imageCache = {}

function sanitizeToken(token) {
    if (!token)
        return ""
    // Strip whitespace / BOM / zero-width chars that break Slack auth
    return ("" + token)
        .replace(/^\uFEFF/, "")
        .replace(/[\u200B-\u200D\uFEFF]/g, "")
        .replace(/\s+/g, "")
}

function setToken(token) {
    _token = sanitizeToken(token)
}

function getToken() {
    return _token
}

function getAuthInfo() {
    return _authInfo
}

function clearCache() {
    _userCache = {}
    _authInfo = null
    _imageCache = {}
}

function userDisplayName(userId) {
    if (!userId)
        return "Unknown"
    var u = _userCache[userId]
    if (!u)
        return userId
    return u.profile && u.profile.display_name
        ? u.profile.display_name
        : (u.real_name || u.name || userId)
}

function getUser(userId) {
    return _userCache[userId] || null
}

function _encodeArgs(args) {
    var parts = []
    for (var key in args) {
        if (!args.hasOwnProperty(key))
            continue
        var value = args[key]
        if (value === undefined || value === null)
            continue
        if (typeof value === "object")
            value = JSON.stringify(value)
        parts.push(encodeURIComponent(key) + "=" + encodeURIComponent(value))
    }
    return parts.join("&")
}

function _parseRetryAfter(xhr) {
    var header = xhr.getResponseHeader("Retry-After")
    if (header) {
        var seconds = parseInt(header, 10)
        if (!isNaN(seconds) && seconds > 0)
            return seconds * 1000
    }
    return 2000
}

function api(method, args, callback, attempt) {
    if (!callback)
        callback = function() {}
    if (attempt === undefined)
        attempt = 0

    var params = args ? JSON.parse(JSON.stringify(args)) : {}
    // QML XMLHttpRequest often drops Authorization; Slack accepts token as a POST param
    if (_token && !params.token)
        params.token = _token

    var xhr = new XMLHttpRequest()
    var url = API_BASE + method
    var body = _encodeArgs(params)

    xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE)
            return

        if (xhr.status === 0) {
            callback({
                ok: false,
                error: "network_error",
                status: 0,
                message: "Network error — check connectivity and AppArmor networking"
            })
            return
        }

        if (xhr.status === 429 && attempt < 3) {
            var delay = _parseRetryAfter(xhr)
            _retryLater(method, args, callback, attempt + 1, delay)
            return
        }

        var response = null
        try {
            response = JSON.parse(xhr.responseText || "{}")
        } catch (e) {
            callback({
                ok: false,
                error: "invalid_json",
                status: xhr.status,
                message: "Failed to parse Slack response"
            })
            return
        }

        if (xhr.status < 200 || xhr.status >= 300) {
            callback({
                ok: false,
                error: response.error || "http_error",
                status: xhr.status,
                message: _friendlyError(response.error) || ("HTTP " + xhr.status)
            })
            return
        }

        if (response.ok === false && response.error === "ratelimited" && attempt < 3) {
            _retryLater(method, args, callback, attempt + 1, _parseRetryAfter(xhr))
            return
        }

        if (response.ok === false && response.error)
            response.message = _friendlyError(response.error)

        callback(response)
    }

    xhr.open("POST", url)
    xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded")
    // Prefer header when the stack supports it; body token is the reliable fallback
    if (_token)
        xhr.setRequestHeader("Authorization", "Bearer " + _token)
    xhr.send(body)
}

function _friendlyError(code) {
    if (!code)
        return ""
    if (code === "invalid_auth")
        return "invalid_auth — use a User OAuth Token (xoxp-…), not a bot token (xoxb-). Reinstall the app to your workspace after adding user scopes."
    if (code === "token_revoked" || code === "token_expired")
        return code + " — generate a fresh User OAuth Token from the Slack app OAuth page."
    if (code === "missing_scope")
        return "missing_scope — add the required User Token Scopes and reinstall the app."
    if (code === "not_authed")
        return "not_authed — no token was sent; try pasting the token again."
    return code
}

// QML JS has no setTimeout; callers should prefer Timer. We expose a hook.
var _retryScheduler = null

function setRetryScheduler(fn) {
    _retryScheduler = fn
}

function _retryLater(method, args, callback, attempt, delayMs) {
    if (_retryScheduler) {
        _retryScheduler(delayMs, function() {
            api(method, args, callback, attempt)
        })
        return
    }
    // Fallback: immediate retry (better than dropping the request)
    api(method, args, callback, attempt)
}

function authTest(callback) {
    api("auth.test", {}, function(res) {
        if (res && res.ok) {
            _authInfo = {
                userId: res.user_id,
                user: res.user,
                team: res.team,
                teamId: res.team_id,
                url: res.url
            }
        }
        callback(res)
    })
}

function conversationsListPage(cursor, callback) {
    var args = {
        types: "public_channel,private_channel,im,mpim",
        exclude_archived: true,
        limit: 200
    }
    if (cursor)
        args.cursor = cursor
    api("conversations.list", args, callback)
}

function conversationsListAll(callback) {
    var all = []

    function next(cursor) {
        conversationsListPage(cursor, function(res) {
            if (!res || !res.ok) {
                callback(res || { ok: false, error: "unknown" })
                return
            }
            var channels = res.channels || []
            for (var i = 0; i < channels.length; i++)
                all.push(channels[i])

            var nextCursor = res.response_metadata && res.response_metadata.next_cursor
                ? res.response_metadata.next_cursor
                : ""
            if (nextCursor)
                next(nextCursor)
            else
                callback({ ok: true, channels: all })
        })
    }

    next("")
}

function usersListPage(cursor, callback) {
    var args = { limit: 200 }
    if (cursor)
        args.cursor = cursor
    api("users.list", args, callback)
}

function usersListAll(callback) {
    function next(cursor) {
        usersListPage(cursor, function(res) {
            if (!res || !res.ok) {
                callback(res || { ok: false, error: "unknown" })
                return
            }
            var members = res.members || []
            for (var i = 0; i < members.length; i++) {
                var m = members[i]
                if (m && m.id)
                    _userCache[m.id] = m
            }
            var nextCursor = res.response_metadata && res.response_metadata.next_cursor
                ? res.response_metadata.next_cursor
                : ""
            if (nextCursor)
                next(nextCursor)
            else
                callback({ ok: true, users: _userCache })
        })
    }
    next("")
}

function conversationsHistory(channelId, options, callback) {
    var args = {
        channel: channelId,
        limit: (options && options.limit) ? options.limit : 50
    }
    if (options && options.oldest)
        args.oldest = options.oldest
    if (options && options.latest)
        args.latest = options.latest
    if (options && options.cursor)
        args.cursor = options.cursor
    api("conversations.history", args, callback)
}

function chatPostMessage(channelId, text, callback) {
    api("chat.postMessage", {
        channel: channelId,
        text: text
    }, callback)
}

function _guessMimeFromName(name) {
    var n = (name || "").toLowerCase()
    if (/\.png$/.test(n)) return "image/png"
    if (/\.jpe?g$/.test(n)) return "image/jpeg"
    if (/\.gif$/.test(n)) return "image/gif"
    if (/\.webp$/.test(n)) return "image/webp"
    if (/\.bmp$/.test(n)) return "image/bmp"
    if (/\.mp4$/.test(n)) return "video/mp4"
    if (/\.webm$/.test(n)) return "video/webm"
    if (/\.pdf$/.test(n)) return "application/pdf"
    return "application/octet-stream"
}

function _basenameFromUrl(url) {
    var s = ("" + (url || "")).split("?")[0]
    var parts = s.split("/")
    var name = parts.length ? parts[parts.length - 1] : "upload"
    try {
        name = decodeURIComponent(name)
    } catch (e) {}
    if (!name || name.length === 0)
        name = "upload"
    return name
}

function _readLocalFileBytes(fileUrl, callback) {
    if (!callback)
        callback = function() {}
    if (!fileUrl) {
        callback(null, "missing_path")
        return
    }
    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE)
            return
        if (xhr.status !== 0 && (xhr.status < 200 || xhr.status >= 300)) {
            callback(null, "read_failed_" + xhr.status)
            return
        }
        var bytes = null
        try {
            if (typeof Uint8Array !== "undefined" && xhr.response && typeof xhr.response !== "string")
                bytes = new Uint8Array(xhr.response)
        } catch (e) {}
        if (!bytes) {
            try {
                var text = xhr.responseText || ""
                bytes = []
                for (var i = 0; i < text.length; i++)
                    bytes.push(text.charCodeAt(i) & 0xff)
            } catch (e2) {
                callback(null, "read_failed")
                return
            }
        }
        if (!bytes || bytes.length === 0) {
            callback(null, "empty_file")
            return
        }
        callback(bytes, "")
    }
    xhr.open("GET", fileUrl)
    try {
        xhr.responseType = "arraybuffer"
    } catch (e3) {}
    xhr.send()
}

function _postUploadBytes(uploadUrl, bytes, callback) {
    if (!callback)
        callback = function() {}
    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE)
            return
        if (xhr.status >= 200 && xhr.status < 300)
            callback(true, "")
        else {
            console.log("[upload] POST to upload_url failed", xhr.status)
            callback(false, "upload_http_" + xhr.status)
        }
    }
    xhr.open("POST", uploadUrl)
    // QML XHR is most reliable with a binary Latin-1 string body
    try {
        var s = ""
        var len = bytes.length
        // Build in chunks to avoid argument limits on some engines
        var chunk = 0x8000
        for (var i = 0; i < len; i += chunk) {
            var end = Math.min(i + chunk, len)
            var piece = []
            for (var j = i; j < end; j++)
                piece.push(String.fromCharCode(bytes[j] & 0xff))
            s += piece.join("")
        }
        xhr.send(s)
    } catch (e) {
        console.log("[upload] send failed", e)
        callback(false, "upload_send_failed")
    }
}

// Upload a local file:// URL into a channel (files.getUploadURLExternal flow)
function uploadLocalFile(channelId, fileUrl, options, callback) {
    if (!callback)
        callback = function() {}
    options = options || {}
    var filename = options.filename || _basenameFromUrl(fileUrl)
    var comment = options.initialComment || options.comment || ""
    var title = options.title || filename

    _readLocalFileBytes(fileUrl, function(bytes, err) {
        if (!bytes) {
            callback({ ok: false, error: err || "read_failed", message: "Could not read the selected file" })
            return
        }
        api("files.getUploadURLExternal", {
            filename: filename,
            length: bytes.length
        }, function(res) {
            if (!res || !res.ok) {
                callback(res || { ok: false, error: "get_upload_url_failed", message: "Could not start upload" })
                return
            }
            var uploadUrl = res.upload_url
            var fileId = res.file_id
            if (!uploadUrl || !fileId) {
                callback({ ok: false, error: "invalid_upload_session", message: "Slack did not return an upload URL" })
                return
            }
            _postUploadBytes(uploadUrl, bytes, function(ok, upErr) {
                if (!ok) {
                    callback({ ok: false, error: upErr || "upload_failed", message: "Failed to upload file bytes" })
                    return
                }
                var completeArgs = {
                    files: [{ id: fileId, title: title }],
                    channel_id: channelId
                }
                if (comment && ("" + comment).trim().length > 0)
                    completeArgs.initial_comment = ("" + comment).trim()
                api("files.completeUploadExternal", completeArgs, function(done) {
                    callback(done || { ok: false, error: "complete_failed", message: "Failed to finalize upload" })
                })
            })
        })
    })
}

function usersInfo(userId, callback) {
    if (_userCache[userId]) {
        callback({ ok: true, user: _userCache[userId] })
        return
    }
    api("users.info", { user: userId }, function(res) {
        if (res && res.ok && res.user)
            _userCache[res.user.id] = res.user
        callback(res)
    })
}

function getCachedUsers() {
    return _userCache
}

function conversationsOpen(userIds, callback) {
    // users is a JSON-encoded array string for form-urlencoded Slack APIs
    var ids = userIds || []
    api("conversations.open", {
        users: JSON.stringify(ids),
        return_im: true
    }, callback)
}

function conversationsJoin(channelId, callback) {
    api("conversations.join", {
        channel: channelId
    }, callback)
}

// Keep only conversations that have at least one message (drops empty DM stubs).
// Runs a few history probes in parallel to stay under rate limits.
function filterItemsWithMessages(items, callback) {
    if (!callback)
        callback = function() {}
    if (!items || items.length === 0) {
        callback([])
        return
    }

    var result = []
    var index = 0
    var inFlight = 0
    var finished = 0
    var concurrency = 3
    var total = items.length

    function startNext() {
        while (inFlight < concurrency && index < total) {
            (function(item) {
                inFlight++
                conversationsHistory(item.id, { limit: 1 }, function(res) {
                    inFlight--
                    finished++
                    if (res && res.ok && res.messages && res.messages.length > 0) {
                        var ts = parseFloat(res.messages[0].ts)
                        if (!isNaN(ts))
                            item.lastActivityTs = ts
                        result.push(item)
                    }
                    if (finished >= total) {
                        // Preserve original relative order among kept items
                        result.sort(function(a, b) {
                            if (a.sortKey < b.sortKey)
                                return -1
                            if (a.sortKey > b.sortKey)
                                return 1
                            return 0
                        })
                        callback(result)
                    } else {
                        startNext()
                    }
                })
            })(items[index++])
        }
    }

    startNext()
}

function _bytesToBase64(bytes) {
    var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    var out = ""
    var i = 0
    var len = bytes.length
    while (i < len) {
        var a = bytes[i++]
        var hasB = i < len
        var b = hasB ? bytes[i++] : 0
        var hasC = i < len
        var c = hasC ? bytes[i++] : 0
        var bitmap = (a << 16) | (b << 8) | c
        out += chars.charAt((bitmap >> 18) & 63)
        out += chars.charAt((bitmap >> 12) & 63)
        out += hasB ? chars.charAt((bitmap >> 6) & 63) : "="
        out += hasC ? chars.charAt(bitmap & 63) : "="
    }
    return out
}

function clearImageCache() {
    _imageCache = {}
}

function _sniffImageMime(bytes) {
    if (!bytes || bytes.length < 12)
        return ""
    // JPEG
    if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff)
        return "image/jpeg"
    // PNG
    if (bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47)
        return "image/png"
    // GIF
    if (bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46)
        return "image/gif"
    // WEBP: RIFF....WEBP
    if (bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46
            && bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50)
        return "image/webp"
    // BMP
    if (bytes[0] === 0x42 && bytes[1] === 0x4d)
        return "image/bmp"
    return ""
}

function _bytesLookLikeHtml(bytes) {
    if (!bytes || bytes.length < 1)
        return false
    var i = 0
    // skip BOM / whitespace
    while (i < bytes.length && (bytes[i] === 0xef || bytes[i] === 0xbb || bytes[i] === 0xbf
            || bytes[i] === 0x20 || bytes[i] === 0x09 || bytes[i] === 0x0a || bytes[i] === 0x0d)) {
        i++
    }
    return i < bytes.length && bytes[i] === 0x3c // '<'
}

function _responseToBytes(xhr) {
    try {
        if (typeof Uint8Array !== "undefined" && xhr.response && typeof xhr.response !== "string")
            return new Uint8Array(xhr.response)
    } catch (e) {}
    try {
        var text = xhr.responseText || ""
        var arr = new Array(text.length)
        for (var i = 0; i < text.length; i++)
            arr[i] = text.charCodeAt(i) & 0xff
        return arr
    } catch (e2) {
        return null
    }
}

function _authedImageUrl(url) {
    if (!_token || !url)
        return url
    // QML XHR often drops Authorization on cross-origin GETs; Slack accepts token= query
    if (/[?&]token=/.test(url))
        return url
    return url + (url.indexOf("?") >= 0 ? "&" : "?") + "token=" + encodeURIComponent(_token)
}

// Fetch a (possibly private) Slack image and return a data: URI for Image.source
function fetchImageAsDataUrl(url, mimetype, callback) {
    if (!callback)
        callback = function() {}
    if (!url) {
        callback("")
        return
    }
    if (_imageCache[url]) {
        callback(_imageCache[url])
        return
    }

    // Public non-Slack URLs can be used directly by Image
    var needsAuth = /slack\.com|slack-edge\.com|slack-files\.com|slack-imgs\.com/i.test(url)
    if (!needsAuth) {
        _imageCache[url] = url
        callback(url)
        return
    }

    var fetchUrl = _authedImageUrl(url)
    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE)
            return
        if (xhr.status < 200 || xhr.status >= 300) {
            console.log("[image] fetch failed", xhr.status, url)
            callback("")
            return
        }

        var headerMime = xhr.getResponseHeader("Content-Type") || ""
        if (headerMime.indexOf(";") !== -1)
            headerMime = headerMime.split(";")[0].trim()
        headerMime = (headerMime || "").toLowerCase()

        var bytes = _responseToBytes(xhr)
        if (!bytes || bytes.length < 8) {
            console.log("[image] empty body", url)
            callback("")
            return
        }

        if (_bytesLookLikeHtml(bytes) || headerMime.indexOf("text/html") === 0 || headerMime.indexOf("application/json") === 0) {
            console.log("[image] got non-image payload", headerMime || "unknown", url)
            callback("")
            return
        }

        var sniffed = _sniffImageMime(bytes)
        var mime = sniffed || mimetype || headerMime || "image/jpeg"
        if (mime.indexOf("image/") !== 0) {
            console.log("[image] unsupported mime", mime, url)
            callback("")
            return
        }
        if (!sniffed) {
            // Header claimed image but bytes don't match — still reject to avoid Qt errors
            console.log("[image] bytes are not a known image format", url)
            callback("")
            return
        }

        try {
            var dataUrl = "data:" + mime + ";base64," + _bytesToBase64(bytes)
            _imageCache[url] = dataUrl
            callback(dataUrl)
        } catch (e) {
            console.log("[image] encode failed", e)
            callback("")
        }
    }

    xhr.open("GET", fetchUrl)
    try {
        xhr.responseType = "arraybuffer"
    } catch (e3) {}
    xhr.setRequestHeader("Accept", "image/*,*/*;q=0.8")
    if (_token)
        xhr.setRequestHeader("Authorization", "Bearer " + _token)
    xhr.send()
}
