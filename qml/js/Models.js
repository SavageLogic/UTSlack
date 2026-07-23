.pragma library
.import "SlackClient.js" as Slack

function conversationTitle(channel) {
    if (!channel)
        return ""
    if (channel.is_im) {
        return Slack.userDisplayName(channel.user)
    }
    if (channel.is_mpim) {
        return channel.name || "Group DM"
    }
    var prefix = channel.is_private ? "🔒 " : "# "
    return prefix + (channel.name || channel.id)
}

function conversationSortKey(channel) {
    if (!channel)
        return "zzz"
    if (channel.is_im)
        return "2:" + conversationTitle(channel).toLowerCase()
    if (channel.is_mpim)
        return "1:" + conversationTitle(channel).toLowerCase()
    return "0:" + (channel.name || "").toLowerCase()
}

function conversationSubtitle(channel) {
    if (!channel)
        return ""
    if (channel.is_im)
        return "Direct message"
    if (channel.is_mpim)
        return "Group message"
    if (channel.is_private)
        return "Private channel"
    return "Channel"
}

function normalizeConversations(channels) {
    var items = []
    if (!channels)
        return items
    for (var i = 0; i < channels.length; i++) {
        var c = channels[i]
        if (!c || c.is_archived)
            continue
        // Sidebar: only existing memberships / open DMs — never invent rows from users.list
        if (c.is_im || c.is_mpim) {
            // keep open DM / group DM conversations only (empties filtered later)
        } else if (c.is_member !== true) {
            // public channels you're not in stay out of the main list
            continue
        }
        var activity = 0
        if (c.updated)
            activity = Number(c.updated)
        else if (c.created)
            activity = Number(c.created)
        items.push({
            id: c.id,
            name: c.name || "",
            title: conversationTitle(c),
            subtitle: conversationSubtitle(c),
            sortKey: conversationSortKey(c),
            isIm: !!c.is_im,
            isMpim: !!c.is_mpim,
            isPrivate: !!c.is_private,
            isChannel: !c.is_im && !c.is_mpim,
            userId: c.user || "",
            lastActivityTs: activity,
            raw: c
        })
    }
    items.sort(function(a, b) {
        if (a.sortKey < b.sortKey)
            return -1
        if (a.sortKey > b.sortKey)
            return 1
        return 0
    })
    return items
}

function isActiveWithinDays(item, days) {
    if (!item)
        return false
    var d = days || 30
    var cutoff = (Date.now() / 1000) - (d * 24 * 60 * 60)
    return (item.lastActivityTs || 0) >= cutoff
}

function splitChannelsByActivity(channels, days) {
    var active = []
    var inactive = []
    if (!channels)
        return { active: active, inactive: inactive }
    for (var i = 0; i < channels.length; i++) {
        if (isActiveWithinDays(channels[i], days))
            active.push(channels[i])
        else
            inactive.push(channels[i])
    }
    return { active: active, inactive: inactive }
}

function splitConversationGroups(items) {
    var channels = []
    var dms = []
    if (!items)
        return { channels: channels, dms: dms }
    for (var i = 0; i < items.length; i++) {
        var it = items[i]
        if (it.isIm || it.isMpim)
            dms.push(it)
        else
            channels.push(it)
    }
    return { channels: channels, dms: dms }
}

function normalizeUsersForPicker(usersMap, selfUserId, existingImUserIds) {
    var items = []
    if (!usersMap)
        return items
    var existing = existingImUserIds || {}
    for (var id in usersMap) {
        if (!usersMap.hasOwnProperty(id))
            continue
        var u = usersMap[id]
        if (!u || u.deleted || u.is_bot || u.id === "USLACKBOT")
            continue
        if (selfUserId && u.id === selfUserId)
            continue
        var name = u.profile && u.profile.display_name
            ? u.profile.display_name
            : (u.real_name || u.name || u.id)
        var real = u.real_name || u.name || ""
        items.push({
            id: u.id,
            title: name,
            subtitle: real && real !== name ? real : (existing[u.id] ? "Existing DM" : "Start a DM"),
            kind: "user",
            hasConversation: !!existing[u.id],
            conversationId: existing[u.id] || "",
            sortKey: (name || "").toLowerCase()
        })
    }
    items.sort(function(a, b) {
        if (a.sortKey < b.sortKey)
            return -1
        if (a.sortKey > b.sortKey)
            return 1
        return 0
    })
    return items
}

function normalizeChannelsForPicker(channels, existingChannelIds) {
    var items = []
    if (!channels)
        return items
    var existing = existingChannelIds || {}
    for (var i = 0; i < channels.length; i++) {
        var c = channels[i]
        if (!c || c.is_archived || c.is_im || c.is_mpim)
            continue
        var member = c.is_member === true
        items.push({
            id: c.id,
            name: c.name || "",
            title: (c.is_private ? "🔒 " : "# ") + (c.name || c.id),
            subtitle: member ? "Open channel" : (c.is_private ? "Private channel" : "Join channel"),
            kind: "channel",
            isPrivate: !!c.is_private,
            isMember: member,
            hasConversation: !!existing[c.id],
            sortKey: (c.name || "").toLowerCase()
        })
    }
    items.sort(function(a, b) {
        // Members first, then alphabetical
        if (a.isMember !== b.isMember)
            return a.isMember ? -1 : 1
        if (a.sortKey < b.sortKey)
            return -1
        if (a.sortKey > b.sortKey)
            return 1
        return 0
    })
    return items
}

function formatTs(ts) {
    if (!ts)
        return ""
    var seconds = parseFloat(ts)
    if (isNaN(seconds))
        return ""
    var d = new Date(seconds * 1000)
    var h = d.getHours()
    var m = d.getMinutes()
    var hh = h < 10 ? "0" + h : "" + h
    var mm = m < 10 ? "0" + m : "" + m
    return hh + ":" + mm
}

function formatDay(ts) {
    if (!ts)
        return ""
    var seconds = parseFloat(ts)
    if (isNaN(seconds))
        return ""
    var d = new Date(seconds * 1000)
    return d.toLocaleDateString()
}

function escapeHtml(text) {
    if (!text)
        return ""
    return ("" + text)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
}

function stripMrkdwn(text) {
    if (!text)
        return ""
    var t = text
    t = t.replace(/<@([A-Z0-9]+)(\|([^>]+))?>/g, function(_, id, _p, name) {
        if (name)
            return name
        return Slack.userDisplayName(id)
    })
    t = t.replace(/<#([A-Z0-9]+)(\|([^>]+))?>/g, function(_, id, _p, name) {
        return name ? ("#" + name) : "#channel"
    })
    // Links <url|label> or <url>
    t = t.replace(/<((?:https?:\/\/|mailto:)[^|>]+)(?:\|([^>]+))?>/gi, function(_, url, label) {
        return label || url
    })
    t = t.replace(/<([^>]+)>/g, "$1")
    t = t.replace(/\*([^*]+)\*/g, "$1")
    t = t.replace(/_([^_]+)_/g, "$1")
    t = t.replace(/`([^`]+)`/g, "$1")
    return t
}

// HTML for RichText labels — Slack links + bare URLs become <a href>
function formatMessageHtml(text) {
    if (!text)
        return ""

    var links = []
    function stashLink(url, label) {
        var idx = links.length
        links.push({ url: url, label: label || url })
        return "%%LINK" + idx + "%%"
    }

    var t = "" + text

    // Slack-formatted links
    t = t.replace(/<((?:https?:\/\/|mailto:)[^|>]+)(?:\|([^>]+))?>/gi, function(_, url, label) {
        return stashLink(url, label)
    })

    // Mentions / channels → plain text markers first
    t = t.replace(/<@([A-Z0-9]+)(\|([^>]+))?>/g, function(_, id, _p, name) {
        return name || Slack.userDisplayName(id)
    })
    t = t.replace(/<#([A-Z0-9]+)(\|([^>]+))?>/g, function(_, id, _p, name) {
        return name ? ("#" + name) : "#channel"
    })
    // Leftover angle brackets (e.g. <!here>)
    t = t.replace(/<([^>]+)>/g, "$1")

    t = escapeHtml(t)

    // Light mrkdwn
    t = t.replace(/\*([^*]+)\*/g, "<b>$1</b>")
    t = t.replace(/_([^_]+)_/g, "<i>$1</i>")
    t = t.replace(/`([^`]+)`/g, "<code>$1</code>")

    // Bare URLs (avoid already-stashed markers)
    t = t.replace(/(https?:\/\/[^\s<&]+)/g, function(url) {
        // Trim common trailing punctuation
        var trailing = ""
        var core = url
        while (core.length && ".,);]}>\"".indexOf(core.charAt(core.length - 1)) !== -1) {
            trailing = core.charAt(core.length - 1) + trailing
            core = core.substring(0, core.length - 1)
        }
        return '<a href="' + core + '">' + core + "</a>" + trailing
    })

    for (var i = 0; i < links.length; i++) {
        var L = links[i]
        var anchor = '<a href="' + escapeHtml(L.url) + '">' + escapeHtml(L.label) + "</a>"
        t = t.split("%%LINK" + i + "%%").join(anchor)
    }

    return t
}

function extractImages(message) {
    var images = []
    if (!message)
        return images

    function pushImage(obj) {
        if (!obj)
            return
        var url = obj.url || obj.thumb || ""
        if (!url)
            return
        // De-dupe by url
        for (var i = 0; i < images.length; i++) {
            if (images[i].url === url || images[i].thumb === url)
                return
        }
        images.push(obj)
    }

    var files = message.files || []
    if ((!files || files.length === 0) && message.file)
        files = [message.file]
    for (var f = 0; f < files.length; f++) {
        var file = files[f]
        if (!file)
            continue
        var mime = (file.mimetype || "").toLowerCase()
        var isImage = mime.indexOf("image/") === 0
                || /\.(png|jpe?g|gif|webp|bmp)$/i.test(file.name || "")
        if (!isImage)
            continue
        var thumb = file.thumb_480 || file.thumb_360 || file.thumb_720
                || file.thumb_800 || file.thumb_160 || file.url_private
        var full = file.url_private_download || file.url_private || thumb
        pushImage({
            id: file.id || "",
            name: file.name || file.title || "image",
            mimetype: mime || "image/jpeg",
            thumb: thumb || full,
            url: full || thumb,
            needsAuth: true
        })
    }

    // Block Kit image blocks
    var blocks = message.blocks || []
    for (var b = 0; b < blocks.length; b++) {
        var block = blocks[b]
        if (!block || block.type !== "image")
            continue
        var blockUrl = block.image_url || ""
        if (blockUrl) {
            pushImage({
                id: "",
                name: block.alt_text || "image",
                mimetype: "image/jpeg",
                thumb: blockUrl,
                url: blockUrl,
                needsAuth: /slack\.com|slack-edge\.com|slack-files\.com|slack-imgs\.com/i.test(blockUrl)
            })
        }
    }

    var atts = message.attachments || []
    for (var a = 0; a < atts.length; a++) {
        var att = atts[a]
        if (!att)
            continue
        var attUrl = att.image_url || att.thumb_url || ""
        if (attUrl) {
            pushImage({
                id: "",
                name: att.title || "image",
                mimetype: "image/jpeg",
                thumb: att.thumb_url || attUrl,
                url: attUrl,
                needsAuth: /slack\.com|slack-edge\.com|slack-files\.com/i.test(attUrl)
            })
        }
    }

    // Image links in message text (public http images)
    var raw = message.text || ""
    var re = /<(https?:\/\/[^|>]+\.(?:png|jpe?g|gif|webp)(?:\?[^|>]*)?)(?:\|[^>]*)?>/gi
    var match
    while ((match = re.exec(raw)) !== null) {
        pushImage({
            id: "",
            name: "image",
            mimetype: "image/jpeg",
            thumb: match[1],
            url: match[1],
            needsAuth: false
        })
    }

    return images
}

function normalizeMessages(messages) {
    var items = []
    if (!messages)
        return items
    // Slack returns newest first; reverse for chronological ListView
    for (var i = messages.length - 1; i >= 0; i--) {
        var m = messages[i]
        if (!m || m.subtype === "channel_join" || m.subtype === "channel_leave")
            continue
        var userId = m.user || (m.bot_id ? m.bot_id : "")
        var author = m.username
            || (userId ? Slack.userDisplayName(userId) : "System")
        var raw = m.text || ""
        var images = extractImages(m)
        items.push({
            ts: m.ts || "",
            userId: userId,
            author: author,
            text: formatMessageHtml(raw),
            plainText: stripMrkdwn(raw),
            rawText: raw,
            imagesJson: JSON.stringify(images),
            hasImages: images.length > 0,
            timeLabel: formatTs(m.ts),
            dayLabel: formatDay(m.ts)
        })
    }
    return items
}
