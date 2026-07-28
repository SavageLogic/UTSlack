.pragma library
.import "SlackClient.js" as Slack
.import "Models.js" as Models

// Protocol helpers for Slack Socket Mode. Transport is RealtimeSocket (QML).

function sanitizeAppToken(token) {
    return Slack.sanitizeToken(token)
}

function isValidAppToken(token) {
    var t = sanitizeAppToken(token)
    return !!(t && t.indexOf("xapp-") === 0)
}

// Open apps.connections.open and return { ok, url, message } via callback.
function fetchConnectionUrl(appToken, callback) {
    if (!callback)
        callback = function() {}
    Slack.appsConnectionsOpen(appToken, function(res) {
        if (!res || !res.ok || !res.url) {
            callback({
                ok: false,
                url: "",
                message: (res && (res.message || res.error)) || "apps.connections.open failed"
            })
            return
        }
        callback({ ok: true, url: res.url, message: "" })
    })
}

function ackEnvelope(socket, envelopeId) {
    if (!socket || !envelopeId)
        return
    try {
        socket.sendText(JSON.stringify({ envelope_id: envelopeId }))
    } catch (e) {
        console.warn("[socketmode] ack failed", e)
    }
}

// Parse a Socket Mode text frame into a normalized realtime payload or null.
// Returns { kind, channelId, message, threadTs, rawEvent } for message events.
function parseFrame(text) {
    if (!text)
        return null
    var msg = null
    try {
        msg = JSON.parse(text)
    } catch (e) {
        return null
    }
    if (!msg || !msg.type)
        return { kind: "unknown", raw: msg }

    if (msg.type === "hello")
        return { kind: "hello", raw: msg }
    if (msg.type === "disconnect")
        return { kind: "disconnect", reason: msg.reason || "", raw: msg }

    if (msg.type === "events_api") {
        var payload = msg.payload || {}
        var event = payload.event || {}
        var out = {
            kind: "events_api",
            envelopeId: msg.envelope_id || "",
            eventType: event.type || "",
            channelId: event.channel || (event.item && event.item.channel) || "",
            rawEvent: event,
            message: null,
            threadTs: ""
        }
        if (event.type === "message") {
            // Skip noisy subtypes for v1 UI (joins, etc.); message_changed later
            var subtype = event.subtype || ""
            if (subtype === "message_deleted" || subtype === "channel_join"
                    || subtype === "channel_leave" || subtype === "message_replied") {
                out.kind = "events_api_ignored"
                return out
            }
            // Bot/message_changed: still try to normalize when text/ts present
            if (subtype === "message_changed" && event.message) {
                var ch = event.channel
                event = event.message
                if (!event.channel && ch)
                    event.channel = ch
            }
            // Prefer explicit channel_type; fall back to Slack ID prefixes (D=IM).
            var channelType = event.channel_type || ""
            out.channelType = channelType
            out.isIm = channelType === "im"
                    || (!channelType && out.channelId && ("" + out.channelId).charAt(0) === "D")
            out.isMpim = channelType === "mpim"
            var normalized = Models.normalizeMessages([event], { chronological: true })
            if (normalized.length > 0) {
                out.message = normalized[0]
                out.threadTs = out.message.threadTs || event.thread_ts || ""
                if (!out.channelId && event.channel)
                    out.channelId = event.channel
                // Recompute after channel fill
                if (!out.channelType && out.channelId && ("" + out.channelId).charAt(0) === "D")
                    out.isIm = true
            }
            console.log("[socketmode] message", out.channelId || "?",
                        "type=" + (channelType || "?"),
                        "im=" + !!out.isIm,
                        "subtype=" + (subtype || "-"),
                        "ts=" + (out.message && out.message.ts ? out.message.ts : "?"),
                        "normalized=" + (out.message ? "yes" : "no"))
        }
        return out
    }

    return { kind: msg.type, raw: msg }
}
