# UTSlack

Native Slack client for [Ubuntu Touch](https://ubuntu-touch.io/), built with QML and the Slack Web API.

## Features (v1)

- Sign in with a Slack **User OAuth Token** (`xoxp-…`)
- Collapsible **Channels** and **Direct messages** groups
- Start a new DM or join/open a channel via **+**
- Read channel/DM history (including inline images and file attachments)
- Search within a conversation
- Send messages and upload photos/files
- Poll for new messages while a chat is open (~8s)
- Push notifications for new messages while the app is running (UBports Push)

## Requirements

- [Clickable](https://clickable-ut.dev/) 8.4.0+
- Ubuntu Touch device (or `clickable desktop` on Linux)
- A Slack app with **user** token scopes (see below)

## Create a Slack app token

1. Open [api.slack.com/apps](https://api.slack.com/apps) → **Create New App** → **From scratch**
2. Under **OAuth & Permissions**, add these **User Token Scopes** (not Bot Token Scopes):

   | Scope | Purpose |
   |-------|---------|
   | `channels:read` | List public channels |
   | `channels:history` | Read public channel messages |
   | `groups:read` | List private channels |
   | `groups:history` | Read private channel messages |
   | `im:read` | List DMs |
   | `im:history` | Read DMs |
   | `mpim:read` | List group DMs |
   | `mpim:history` | Read group DMs |
   | `users:read` | Resolve display names |
   | `chat:write` | Send messages as you |
   | `im:write` | Open new direct messages |
   | `mpim:write` | Open group DMs (optional) |
   | `channels:write` | Join public channels |
   | `files:read` | Display images and file previews |
   | `files:write` | Upload photos and files |
   | `search:read` | Search messages within a conversation |

3. Click **Install to Workspace** and allow access
4. Copy the **User OAuth Token** (`xoxp-…`) — not the bot token
5. Paste it into UTSlack’s Connect screen

## Build and run

```bash
# Desktop (Linux) — force host arch if your Clickable config defaults to arm64
clickable desktop --arch amd64
# or:
clickable script desktop-host

# Install on a connected Ubuntu Touch device
clickable build --arch arm64
clickable install
```

If `clickable desktop` hangs after `XDG_RUNTIME_DIR` / never opens a window, you are almost certainly running an **arm64** build on an **x86_64** PC (see `build/aarch64-linux-gnu` in the log). That comes from `default_arch: arm64` or `always_detect` in `~/.clickable/config.yaml`. Use `--arch amd64` for desktop.

Framework target: `ubuntu-touch-24.04-1.x` (see `clickable.yaml`).

## Notifications

UTSlack registers with **UBports Push** and polls Slack for new messages about every 45s while the app is running (or kept alive in the background). New messages are delivered as system notifications via a push helper.

- Toggle in **Settings → Message notifications**
- Device must be signed in to an **OpenStore / UBports** account (PushClient auth)
- Popups may be suppressed while UTSlack is in the foreground (platform behavior)
- True lock-screen push when the app is fully suspended would need a separate Slack→UBports relay server (not included)

## Project layout

```
qml/
  Main.qml                 # Auth gate, PageStack, PushClient, API façade
  AppTheme.qml             # Adaptive light/dark brand + bubble colors
  pages/                   # Login, conversations, chat, settings
  components/              # List/message/composer widgets
  js/
    SlackClient.js         # Slack Web API + pagination / 429 backoff
    Models.js              # Normalize API payloads for the UI
    Storage.js             # Persist token + notification prefs
    Notify.js              # Unread poller + UBports Push sender
push/
  pushexec                 # Push helper (passthrough)
  push-helper.json
  push-apparmor.json
assets/logo.svg
```

## Privacy

Your token is stored only on-device in the app’s LocalStorage database. Logging out clears it. The app talks directly to `https://slack.com/api/` and `https://push.ubports.com/notify` — there is no intermediate Slack relay server.

## Not in v1

Threads, reactions, search, background daemon when fully suspended, and embedded OAuth (bring-your-own Client ID) are out of scope for this release.

## License

MIT License.
