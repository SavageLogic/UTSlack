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
    var prefix = channel.is_private ? "" : "# "
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
            avatarUrl: (c.is_im && c.user) ? Slack.userAvatarUrl(c.user, 72) : "",
            lastActivityTs: activity,
            hasUnread: false,
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

// Mark hasUnread from last activity vs lastOpenedMap.
// Missing map entries are seeded to current activity (nothing bold until new traffic).
// Returns true if the map gained new keys and should be persisted.
function applyUnreadState(items, lastOpenedMap) {
    var map = lastOpenedMap || {}
    var mapChanged = false
    if (!items)
        return mapChanged
    for (var i = 0; i < items.length; i++) {
        var it = items[i]
        if (!it || !it.id)
            continue
        var latest = Number(it.lastActivityTs) || 0
        var latestStr = latest > 0 ? ("" + latest) : "0"
        if (!map.hasOwnProperty(it.id)) {
            map[it.id] = latestStr
            mapChanged = true
            it.hasUnread = false
            continue
        }
        var opened = parseFloat(map[it.id]) || 0
        it.hasUnread = latest > opened
    }
    return mapChanged
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
            avatarUrl: Slack.userAvatarUrl(u.id, 72),
            isPrivate: false,
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
            title: (c.is_private ? "" : "# ") + (c.name || c.id),
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

function nlToBr(text) {
    return ("" + (text || "")).replace(/\r\n|\r|\n/g, "<br>")
}

function stripMrkdwn(text) {
    if (!text)
        return ""
    var t = text
    t = t.replace(/<@([A-Za-z0-9]+)(?:\|([^>]+))?>/g, function(_, id, name) {
        return "@" + (name || Slack.userDisplayName(id))
    })
    t = t.replace(/<#([A-Za-z0-9]+)(?:\|([^>]+))?>/g, function(_, id, name) {
        return name ? ("#" + name) : "#channel"
    })
    t = t.replace(/<!(here|channel|everyone)(?:\|[^>]*)?>/gi, function(_, kind) {
        return "@" + ("" + kind).toLowerCase()
    })
    t = t.replace(/<!subteam\^[A-Za-z0-9]+(?:\|([^>]+))?>/g, function(_, name) {
        return name || "@group"
    })
    t = t.replace(/<((?:https?:\/\/|mailto:)[^|>]+)(?:\|([^>]+))?>/gi, function(_, url, label) {
        return label || url
    })
    t = t.replace(/<([^>]+)>/g, "$1")
    t = t.replace(/```([\s\S]*?)```/g, "$1")
    t = t.replace(/\*([^*]+)\*/g, "$1")
    t = t.replace(/_([^_\s][^_]*)_/g, "$1")
    t = t.replace(/~([^~]+)~/g, "$1")
    t = t.replace(/`([^`]+)`/g, "$1")
    return t
}

function applyTextStyles(escapedText, style) {
    var t = escapedText || ""
    if (!style)
        return t
    // Innermost → outermost so nested styles remain valid HTML
    if (style.code)
        t = "<tt>" + t + "</tt>"
    if (style.strike)
        t = "<s>" + t + "</s>"
    if (style.italic)
        t = "<i>" + t + "</i>"
    if (style.bold)
        t = "<b>" + t + "</b>"
    return t
}

function formatRichTextLeaf(el) {
    if (!el || !el.type)
        return ""
    switch (el.type) {
    case "text":
        return applyTextStyles(nlToBr(escapeHtml(el.text || "")), el.style)
    case "link": {
        var label = el.text || el.url || ""
        var href = el.url || ""
        return '<a href="' + escapeHtml(href) + '">'
            + applyTextStyles(escapeHtml(label), el.style)
            + "</a>"
    }
    case "user":
        return "<b>" + escapeHtml("@" + Slack.userDisplayName(el.user_id)) + "</b>"
    case "usergroup":
        return "<b>" + escapeHtml(el.usergroup_id ? ("@" + el.usergroup_id) : "@group") + "</b>"
    case "channel":
        return "<b>" + escapeHtml("#" + (el.channel_id || "channel")) + "</b>"
    case "emoji":
        if (el.unicode)
            return escapeHtml(el.unicode)
        return escapeHtml(":" + (el.name || "") + ":")
    case "broadcast":
        return "<b>@" + escapeHtml(el.range || "here") + "</b>"
    case "color":
        return escapeHtml(el.value || "")
    case "date":
        return escapeHtml(el.fallback || ("" + (el.timestamp || "")))
    default:
        if (el.text)
            return escapeHtml(el.text)
        return ""
    }
}

function formatRichTextElements(elements) {
    if (!elements || !elements.length)
        return ""
    var out = ""
    for (var i = 0; i < elements.length; i++)
        out += formatRichTextLeaf(elements[i])
    return out
}

function formatRichTextBlock(block) {
    if (!block || !block.type)
        return ""
    var inner = ""
    var i
    switch (block.type) {
    case "rich_text_section":
        return formatRichTextElements(block.elements)
    case "rich_text_preformatted":
        inner = formatRichTextElements(block.elements)
        return "<pre>" + inner + "</pre>"
    case "rich_text_quote":
        inner = formatRichTextElements(block.elements)
        return "<i>" + inner + "</i><br>"
    case "rich_text_list": {
        var style = block.style === "ordered" ? "ol" : "ul"
        // Qt RichText list support is spotty — use plain bullets/numbers
        var items = block.elements || []
        var lines = []
        for (i = 0; i < items.length; i++) {
            var itemHtml = formatRichTextElements(items[i].elements)
            var prefix = style === "ol" ? ((i + 1) + ". ") : "• "
            lines.push(escapeHtml(prefix) + itemHtml)
        }
        return lines.join("<br>")
    }
    default:
        if (block.elements)
            return formatRichTextElements(block.elements)
        return ""
    }
}

function formatRichTextBlocks(blocks) {
    if (!blocks || !blocks.length)
        return ""
    var parts = []
    for (var i = 0; i < blocks.length; i++) {
        var b = blocks[i]
        if (!b)
            continue
        if (b.type === "rich_text") {
            var els = b.elements || []
            for (var j = 0; j < els.length; j++) {
                var chunk = formatRichTextBlock(els[j])
                if (chunk)
                    parts.push(chunk)
            }
        } else if (b.type === "section" && b.text && b.text.text) {
            if (b.text.type === "mrkdwn")
                parts.push(formatMessageHtml(b.text.text))
            else
                parts.push(nlToBr(escapeHtml(b.text.text)))
        }
    }
    return parts.join("<br>")
}

function stripRichTextLeaf(el) {
    if (!el || !el.type)
        return ""
    switch (el.type) {
    case "text":
        return el.text || ""
    case "link":
        return el.text || el.url || ""
    case "user":
        return "@" + Slack.userDisplayName(el.user_id)
    case "channel":
        return "#" + (el.channel_id || "channel")
    case "emoji":
        return el.unicode || (":" + (el.name || "") + ":")
    case "broadcast":
        return "@" + (el.range || "here")
    case "date":
        return el.fallback || ""
    default:
        return el.text || ""
    }
}

function stripRichTextBlocks(blocks) {
    if (!blocks || !blocks.length)
        return ""
    var parts = []
    function walkElements(elements) {
        var s = ""
        if (!elements)
            return s
        for (var i = 0; i < elements.length; i++)
            s += stripRichTextLeaf(elements[i])
        return s
    }
    for (var i = 0; i < blocks.length; i++) {
        var b = blocks[i]
        if (!b)
            continue
        if (b.type === "rich_text") {
            var els = b.elements || []
            for (var j = 0; j < els.length; j++) {
                var el = els[j]
                if (!el)
                    continue
                if (el.type === "rich_text_list") {
                    var items = el.elements || []
                    for (var k = 0; k < items.length; k++)
                        parts.push(walkElements(items[k].elements))
                } else {
                    parts.push(walkElements(el.elements))
                }
            }
        } else if (b.type === "section" && b.text && b.text.text) {
            parts.push(b.text.type === "mrkdwn" ? stripMrkdwn(b.text.text) : b.text.text)
        }
    }
    return parts.join("\n")
}

function messageHasRichText(message) {
    var blocks = message && message.blocks
    if (!blocks)
        return false
    for (var i = 0; i < blocks.length; i++) {
        if (blocks[i] && blocks[i].type === "rich_text")
            return true
        if (blocks[i] && blocks[i].type === "section" && blocks[i].text && blocks[i].text.text)
            return true
    }
    return false
}

// Prefer structured rich_text; fall back to mrkdwn in text
function formatSlackMessage(message) {
    if (!message)
        return ""
    if (messageHasRichText(message)) {
        var html = formatRichTextBlocks(message.blocks)
        if (html)
            return html
    }
    return formatMessageHtml(message.text || "")
}

function plainSlackMessage(message) {
    if (!message)
        return ""
    if (messageHasRichText(message)) {
        var plain = stripRichTextBlocks(message.blocks)
        if (plain)
            return plain
    }
    return stripMrkdwn(message.text || "")
}

// HTML for RichText labels — Slack mrkdwn → limited Qt HTML
function formatMessageHtml(text) {
    if (!text)
        return ""

    var links = []
    var mentions = []
    var codeBlocks = []
    function stashLink(url, label) {
        var idx = links.length
        links.push({ url: url, label: label || url })
        return "%%LINK" + idx + "%%"
    }
    function stashMention(label) {
        var idx = mentions.length
        mentions.push(label)
        return "%%MENTION" + idx + "%%"
    }
    function stashCodeBlock(body) {
        var idx = codeBlocks.length
        codeBlocks.push(body)
        return "%%CODEBLOCK" + idx + "%%"
    }

    var t = "" + text

    // Fenced code before other transforms
    t = t.replace(/```([\s\S]*?)```/g, function(_, body) {
        return stashCodeBlock(body.replace(/^\n+|\n+$/g, ""))
    })

    // Slack-formatted links
    t = t.replace(/<((?:https?:\/\/|mailto:)[^|>]+)(?:\|([^>]+))?>/gi, function(_, url, label) {
        return stashLink(url, label)
    })

    // User / channel / special mentions
    t = t.replace(/<@([A-Za-z0-9]+)(?:\|([^>]+))?>/g, function(_, id, name) {
        return stashMention("@" + (name || Slack.userDisplayName(id)))
    })
    t = t.replace(/<#([A-Za-z0-9]+)(?:\|([^>]+))?>/g, function(_, id, name) {
        return stashMention(name ? ("#" + name) : "#channel")
    })
    t = t.replace(/<!(here|channel|everyone)(?:\|[^>]*)?>/gi, function(_, kind) {
        return stashMention("@" + ("" + kind).toLowerCase())
    })
    t = t.replace(/<!subteam\^[A-Za-z0-9]+(?:\|([^>]+))?>/g, function(_, name) {
        return stashMention(name || "@group")
    })
    // Leftover angle brackets
    t = t.replace(/<([^>]+)>/g, "$1")

    t = escapeHtml(t)

    // Inline code first so bold/italic inside is left alone
    t = t.replace(/`([^`]+)`/g, "<tt>$1</tt>")
    // Slack mrkdwn emphasis
    t = t.replace(/\*([^*]+)\*/g, "<b>$1</b>")
    t = t.replace(/(^|[\s(])_([^_\s][^_]*)_(?=[\s).,!?:;]|$)/g, "$1<i>$2</i>")
    t = t.replace(/~([^~]+)~/g, "<s>$1</s>")

    // Newlines → br (after escape; markers have no newlines we care about)
    t = nlToBr(t)

    // Bare URLs
    t = t.replace(/(https?:\/\/[^\s<&]+)/g, function(url) {
        var trailing = ""
        var core = url
        while (core.length && ".,);]}>\"".indexOf(core.charAt(core.length - 1)) !== -1) {
            trailing = core.charAt(core.length - 1) + trailing
            core = core.substring(0, core.length - 1)
        }
        return '<a href="' + core + '">' + core + "</a>" + trailing
    })

    for (var ci = 0; ci < codeBlocks.length; ci++) {
        var pre = "<pre>" + escapeHtml(codeBlocks[ci]) + "</pre>"
        t = t.split("%%CODEBLOCK" + ci + "%%").join(pre)
    }

    for (var mi = 0; mi < mentions.length; mi++) {
        var mentionHtml = "<b>" + escapeHtml(mentions[mi]) + "</b>"
        t = t.split("%%MENTION" + mi + "%%").join(mentionHtml)
    }

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
            avatarUrl: userId ? Slack.userAvatarUrl(userId, 72) : "",
            text: formatSlackMessage(m),
            plainText: plainSlackMessage(m),
            rawText: raw,
            imagesJson: JSON.stringify(images),
            hasImages: images.length > 0,
            timeLabel: formatTs(m.ts),
            dayLabel: formatDay(m.ts)
        })
    }
    return items
}

// search.messages hits → list rows for in-conversation search
function normalizeSearchResults(matches) {
    var items = []
    if (!matches)
        return items
    for (var i = 0; i < matches.length; i++) {
        var m = matches[i]
        if (!m)
            continue
        var userId = m.user || ""
        var author = m.username
            || (userId ? Slack.userDisplayName(userId) : "System")
        var raw = m.text || ""
        var channelId = ""
        if (m.channel) {
            if (typeof m.channel === "string")
                channelId = m.channel
            else
                channelId = m.channel.id || ""
        }
        // Search hits rarely include blocks; use full formatter when present
        items.push({
            ts: m.ts || "",
            channelId: channelId,
            userId: userId,
            author: author,
            avatarUrl: userId ? Slack.userAvatarUrl(userId, 72) : "",
            text: formatSlackMessage(m),
            plainText: plainSlackMessage(m),
            rawText: raw,
            timeLabel: formatTs(m.ts),
            dayLabel: formatDay(m.ts)
        })
    }
    return items
}
