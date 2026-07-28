.pragma library
.import "Models.js" as Models

// Parse a relay SSE data payload into the same shape as Socket Mode message events.
// Accepted shapes:
//   { type:"message", channelId|channel, ...slack message fields }
//   { type:"message", channelId, message: { ... } }
//   raw Slack-like message with channel + ts + text

function parseEvent(dataText) {
    if (!dataText)
        return null
    var obj = null
    try {
        obj = JSON.parse(dataText)
    } catch (e) {
        return null
    }
    if (!obj)
        return null

    var channelId = obj.channelId || obj.channel || ""
    var threadTs = obj.threadTs || obj.thread_ts || ""
    var eventType = obj.type || "message"
    var raw = obj.message || obj.event || obj

    if (eventType !== "message" && !(raw && (raw.ts || raw.text)))
        return {
            kind: "relay_other",
            eventType: eventType,
            channelId: channelId,
            message: null,
            threadTs: threadTs,
            rawEvent: obj
        }

    // Ensure channel on the object normalizeMessages will see
    if (!raw.channel && channelId)
        raw.channel = channelId
    if (!raw.thread_ts && threadTs)
        raw.thread_ts = threadTs

    var normalized = Models.normalizeMessages([raw], { chronological: true })
    if (normalized.length === 0)
        return null

    return {
        kind: "relay_message",
        eventType: "message",
        channelId: channelId || raw.channel || "",
        message: normalized[0],
        threadTs: normalized[0].threadTs || threadTs || "",
        rawEvent: obj
    }
}
