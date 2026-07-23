/*
 * Copyright (c) 2026 Kevin Hasselquist
 *
 * SPDX-License-Identifier: MIT
 */

import QtQuick 2.7
import Lomiri.Components 1.3
import Ubuntu.PushNotifications 0.1
import "js/SlackClient.js" as Slack
import "js/Storage.js" as Storage
import "js/Models.js" as Models
import "js/Notify.js" as Notify

MainView {
    id: root
    objectName: "mainView"
    applicationName: "utslack.savagelogic"
    automaticOrientation: true
    // Keep bottom-anchored UI (message composer, etc.) above the OSK
    anchorToKeyboard: true

    width: units.gu(45)
    height: units.gu(75)

    property string userId: ""
    property string userName: ""
    property string teamName: ""
    property bool ready: false
    property bool pendingConversationsReload: false
    property var lastRawChannels: []
    property bool notificationsEnabled: true
    property string pushStatus: ""

    AppTheme {
        id: appTheme
    }
    // Expose adaptive colors to pages/components via app.colors
    property alias colors: appTheme

    // Qt.labs.platform Clipboard is not creatable on UT/clickable desktop.
    // TextEdit.copy() still talks to the system clipboard.
    TextEdit {
        id: clipboardHelper
        visible: false
        text: ""
    }

    function copyTextToClipboard(value) {
        if (!value)
            return false
        clipboardHelper.text = "" + value
        clipboardHelper.selectAll()
        clipboardHelper.copy()
        return true
    }

    // Retry scheduler for SlackClient rate-limit backoff
    QtObject {
        id: retryBridge
        property var queue: []

        function schedule(delayMs, fn) {
            queue.push({ at: Date.now() + delayMs, fn: fn })
            if (!retryTimer.running)
                retryTimer.start()
        }
    }

    Timer {
        id: retryTimer
        interval: 200
        repeat: true
        running: false
        onTriggered: {
            var now = Date.now()
            var remaining = []
            for (var i = 0; i < retryBridge.queue.length; i++) {
                var item = retryBridge.queue[i]
                if (item.at <= now)
                    item.fn()
                else
                    remaining.push(item)
            }
            retryBridge.queue = remaining
            if (remaining.length === 0)
                retryTimer.stop()
        }
    }

    PushClient {
        id: pushClient
        appId: "utslack.savagelogic_utslack"

        onError: {
            console.warn("[push] error:", reason)
            if (reason === "bad auth")
                root.pushStatus = i18n.tr("Sign in to OpenStore / UBports account for push")
            else
                root.pushStatus = reason || i18n.tr("Push error")
        }

        onTokenChanged: {
            Notify.setPushToken(pushClient.token)
            if (pushClient.token) {
                root.pushStatus = i18n.tr("Push registered")
                console.log("[push] token ready")
            }
        }

        onNotificationsChanged: root.handlePushMessages(notifications)
    }

    Timer {
        id: notifyPollTimer
        interval: 45000
        repeat: true
        running: root.ready && root.notificationsEnabled
                 && Qt.application.state !== Qt.ApplicationSuspended
        onTriggered: Notify.pollOnce()
    }

    function setNotificationsEnabled(enabled) {
        notificationsEnabled = !!enabled
        Notify.setEnabled(notificationsEnabled)
        Storage.setNotificationsEnabled(notificationsEnabled)
    }

    function handlePushMessages(messages) {
        if (!messages || messages.length === 0)
            return
        for (var i = 0; i < messages.length; i++) {
            var raw = messages[i]
            var data = raw
            if (typeof raw === "string") {
                try { data = JSON.parse(raw) } catch (e) { continue }
            }
            var msg = data.message || data
            if (msg && msg.channelId) {
                openChatFromNotification(msg.channelId, msg.channelTitle || "")
                return
            }
        }
    }

    function openChatFromNotification(channelId, channelTitle) {
        if (!channelId || !ready)
            return
        pageStack.push(Qt.resolvedUrl("pages/ChatPage.qml"), {
            app: root,
            channelId: channelId,
            channelTitle: channelTitle || i18n.tr("Chat")
        })
    }

    function connectWithToken(token, callback) {
        var cleaned = Slack.sanitizeToken(token)
        if (!cleaned) {
            if (callback)
                callback(false, i18n.tr("Paste a Slack User OAuth Token (xoxp-…)."))
            return
        }
        if (cleaned.indexOf("xoxb-") === 0) {
            if (callback)
                callback(false, i18n.tr("That looks like a Bot token (xoxb-). UTSlack needs a User OAuth Token (xoxp-) from OAuth & Permissions → User OAuth Token."))
            return
        }
        if (cleaned.indexOf("xoxp-") !== 0 && cleaned.indexOf("xoxe-") !== 0) {
            if (callback)
                callback(false, i18n.tr("Token should start with xoxp-. Copy the User OAuth Token after installing the app to your workspace."))
            return
        }

        Slack.setToken(cleaned)
        Slack.authTest(function(res) {
            if (!res || !res.ok) {
                Slack.setToken("")
                if (callback)
                    callback(false, (res && (res.message || res.error)) || i18n.tr("Invalid token"))
                return
            }
            Storage.setToken(cleaned)
            applyAuth(res)
            showConversations()
            if (callback)
                callback(true, "")
        })
    }

    function applyAuth(res) {
        userId = res.user_id || ""
        userName = res.user || ""
        teamName = res.team || ""
        ready = true
        Notify.setSelfUserId(userId)
        Notify.loadPrefs()
        notificationsEnabled = Notify.isEnabled()
    }

    function logout() {
        Storage.clearToken()
        Slack.setToken("")
        Slack.clearCache()
        Notify.setConversations([])
        userId = ""
        userName = ""
        teamName = ""
        ready = false
        pageStack.clear()
        pageStack.push(Qt.resolvedUrl("pages/LoginPage.qml"), { app: root })
    }

    function showConversations() {
        pageStack.clear()
        pageStack.push(Qt.resolvedUrl("pages/ConversationsPage.qml"), { app: root })
    }

    function updateNotifyWatchList(items) {
        var sorted = (items || []).slice().sort(function(a, b) {
            return (b.lastActivityTs || 0) - (a.lastActivityTs || 0)
        })
        Notify.setConversations(sorted)
        Notify.initializeSeenBaselines()
    }

    function loadConversations(callback) {
        Slack.usersListAll(function(usersRes) {
            Slack.conversationsListAll(function(res) {
                if (!res || !res.ok) {
                    callback(false, [], (res && (res.message || res.error)) || i18n.tr("API error"))
                    return
                }
                lastRawChannels = res.channels || []
                var items = Models.normalizeConversations(lastRawChannels)
                var groups = Models.splitConversationGroups(items)

                Slack.filterItemsWithMessages(groups.dms, function(dmsWithMessages) {
                    var merged = (groups.channels || []).concat(dmsWithMessages || [])
                    merged.sort(function(a, b) {
                        if (a.sortKey < b.sortKey)
                            return -1
                        if (a.sortKey > b.sortKey)
                            return 1
                        return 0
                    })
                    var openedMap = Storage.getLastOpenedMap()
                    if (Models.applyUnreadState(merged, openedMap))
                        Storage.setLastOpenedMap(openedMap)
                    updateNotifyWatchList(merged)
                    callback(true, merged, "")
                })
            })
        })
    }

    function loadPickerData(callback) {
        function finish(channels) {
            lastRawChannels = channels || lastRawChannels || []
            var existing = Models.normalizeConversations(lastRawChannels)
            var imByUser = {}
            var channelIds = {}
            for (var i = 0; i < existing.length; i++) {
                if (existing[i].isIm && existing[i].userId)
                    imByUser[existing[i].userId] = existing[i].id
                if (existing[i].isChannel)
                    channelIds[existing[i].id] = true
            }
            var people = Models.normalizeUsersForPicker(Slack.getCachedUsers(), userId, imByUser)
            var chans = Models.normalizeChannelsForPicker(lastRawChannels, channelIds)
            callback(true, { people: people, channels: chans }, "")
        }

        Slack.usersListAll(function() {
            if (lastRawChannels && lastRawChannels.length > 0) {
                finish(lastRawChannels)
                return
            }
            Slack.conversationsListAll(function(res) {
                if (!res || !res.ok) {
                    callback(false, null, (res && (res.message || res.error)) || i18n.tr("API error"))
                    return
                }
                finish(res.channels || [])
            })
        })
    }

    function openDirectMessage(userId, callback) {
        Slack.conversationsOpen([userId], function(res) {
            if (!res || !res.ok) {
                callback(false, null, (res && (res.message || res.error)) || i18n.tr("Could not open DM"))
                return
            }
            var ch = res.channel || {}
            callback(true, {
                id: ch.id,
                title: Models.conversationTitle(ch) || Slack.userDisplayName(userId)
            }, "")
        })
    }

    function openChannelConversation(channelId, isMember, callback) {
        function done(ch) {
            callback(true, {
                id: ch.id || channelId,
                title: Models.conversationTitle(ch) || ("# " + (ch.name || channelId))
            }, "")
        }
        if (isMember) {
            done({ id: channelId })
            return
        }
        Slack.conversationsJoin(channelId, function(res) {
            if (!res || !res.ok) {
                callback(false, null, (res && (res.message || res.error)) || i18n.tr("Could not join channel"))
                return
            }
            done(res.channel || { id: channelId })
        })
    }

    function loadMessages(channelId, options, callback) {
        Slack.conversationsHistory(channelId, options || {}, function(res) {
            if (!res || !res.ok) {
                callback(false, [], (res && (res.message || res.error)) || i18n.tr("API error"))
                return
            }
            var raw = res.messages || []
            var ids = Slack.collectUserIdsFromMessages(raw)
            Slack.ensureUsersCached(ids, function() {
                var items = Models.normalizeMessages(raw)
                callback(true, items, "")
            })
        })
    }

    function searchInChannel(channelId, query, callback) {
        var q = ("" + (query || "")).trim()
        if (!channelId || !q) {
            callback(true, [], "")
            return
        }
        var fullQuery = "in:" + channelId + " " + q
        Slack.searchMessages(fullQuery, { count: 25, sort: "timestamp", sort_dir: "desc" }, function(res) {
            if (!res || !res.ok) {
                var err = (res && res.error) || "api_error"
                var msg = (res && res.message) || ""
                if (err === "missing_scope" || err === "not_allowed_token_type")
                    msg = i18n.tr("Search needs the search:read user scope. Add it in your Slack app OAuth settings, reinstall the app, and paste a new token.")
                else if (!msg)
                    msg = i18n.tr("Search failed")
                callback(false, [], msg)
                return
            }
            var matches = (res.messages && res.messages.matches) ? res.messages.matches : []
            var ids = Slack.collectUserIdsFromMessages(matches)
            Slack.ensureUsersCached(ids, function() {
                callback(true, Models.normalizeSearchResults(matches), "")
            })
        })
    }

    // Load messages around a timestamp so we can jump to a search hit
    function loadMessagesAround(channelId, ts, callback) {
        if (!channelId || !ts) {
            callback(false, [], "", "")
            return
        }
        // History is newest-first from Slack; request a window ending at ts (inclusive)
        Slack.conversationsHistory(channelId, {
            latest: ts,
            inclusive: true,
            limit: 40
        }, function(res) {
            if (!res || !res.ok) {
                callback(false, [], (res && (res.message || res.error)) || i18n.tr("API error"), ts)
                return
            }
            var raw = res.messages || []
            var ids = Slack.collectUserIdsFromMessages(raw)
            Slack.ensureUsersCached(ids, function() {
                callback(true, Models.normalizeMessages(raw), "", ts)
            })
        })
    }

    function searchMentions(query) {
        return Slack.searchUsersForMention(query, 8)
    }

    function sendMessage(channelId, text, callback) {
        var encoded = Slack.encodeTextMentions(text || "")
        Slack.chatPostMessage(channelId, encoded, function(res) {
            if (!res || !res.ok) {
                callback(false, (res && (res.message || res.error)) || i18n.tr("Send failed"))
                return
            }
            callback(true, "")
        })
    }

    function uploadFile(channelId, fileUrl, options, callback) {
        var opts = options || {}
        if (opts.initialComment)
            opts.initialComment = Slack.encodeTextMentions(opts.initialComment)
        Slack.uploadLocalFile(channelId, fileUrl, opts, function(res) {
            if (!res || !res.ok) {
                callback(false, (res && (res.message || res.error)) || i18n.tr("Upload failed"))
                return
            }
            callback(true, "")
        })
    }

    function copyImageToClipboard(info, callback) {
        if (!callback)
            callback = function() {}
        if (!info) {
            callback(false, i18n.tr("No image to copy"))
            return
        }

        // Pure-QML build: system image clipboard needs a native helper.
        // For public image URLs we copy the link; private Slack files must be downloaded.
        var url = info.url || info.thumb || ""
        var needsAuth = info.needsAuth !== false
        if (!url) {
            callback(false, i18n.tr("No image to copy"))
            return
        }
        if (needsAuth) {
            callback(false, i18n.tr("Private Slack images can't be copied yet — use Download"))
            return
        }
        if (copyTextToClipboard(url))
            callback(true, "")
        else
            callback(false, i18n.tr("Couldn't copy image link"))
    }

    function markChannelSeen(channelId, ts) {
        Notify.markSeen(channelId, ts)
        Storage.markChannelOpened(channelId, ts)
    }

    function refreshConversationUnread(items) {
        var list = items || []
        var openedMap = Storage.getLastOpenedMap()
        if (Models.applyUnreadState(list, openedMap))
            Storage.setLastOpenedMap(openedMap)
        return list
    }

    function hideConversation(channelId) {
        Storage.setConversationHidden(channelId, true)
    }

    function unhideConversation(channelId) {
        Storage.setConversationHidden(channelId, false)
    }

    function isConversationHidden(channelId) {
        return Storage.isConversationHidden(channelId)
    }

    function getChannelNotifyMode(channelId) {
        return Storage.getEffectiveNotifyMode(channelId)
    }

    // mode: "all" | "mentions" | "mute"
    // options.muteUntil: epoch ms for temporary mute
    // Permanent mute best-effort syncs to Slack via undocumented users.prefs.set.
    function setChannelNotifyPref(channelId, mode, options, callback) {
        if (!callback)
            callback = function() {}
        options = options || {}
        var muteUntil = options.muteUntil || 0
        var effectiveMode = mode || "all"
        Storage.setChannelNotifyPref(channelId, effectiveMode, muteUntil)

        // Temporary mutes and mentions are local (no public Slack API).
        // Permanent mute: try syncing muted_channels on Slack.
        if (effectiveMode === "mute" && !muteUntil) {
            Slack.setChannelMutedOnSlack(channelId, true, function(res) {
                callback(!!(res && res.ok), (res && res.message) || "")
            })
            return
        }
        if (effectiveMode === "all" || effectiveMode === "mentions") {
            Slack.setChannelMutedOnSlack(channelId, false, function(res) {
                // Ignore Slack failures for unmute — local pref still applies
                callback(true, "")
            })
            return
        }
        callback(true, "")
    }

    PageStack {
        id: pageStack
        anchors.fill: parent
    }

    Component.onCompleted: {
        Slack.setRetryScheduler(function(delayMs, fn) {
            retryBridge.schedule(delayMs, fn)
        })
        Notify.loadPrefs()
        notificationsEnabled = Notify.isEnabled()

        var token = Storage.getToken()
        if (token && token.length > 0) {
            Slack.setToken(token)
            Slack.authTest(function(res) {
                if (res && res.ok) {
                    applyAuth(res)
                    showConversations()
                } else {
                    Storage.clearToken()
                    pageStack.push(Qt.resolvedUrl("pages/LoginPage.qml"), { app: root })
                }
            })
        } else {
            pageStack.push(Qt.resolvedUrl("pages/LoginPage.qml"), { app: root })
        }
    }
}
