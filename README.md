# UTSlack

Native Slack client for [Ubuntu Touch](https://ubuntu-touch.io/), built with QML and the Slack Web API.

## Features (v1)

- Sign in with a Slack **User OAuth Token** (`xoxp-…`)
- Collapsible **Channels** and **Direct messages** groups
- Start a new DM or join/open a channel via **+**
- Read channel/DM history (including inline images and file attachments)
- Open **threads**, read replies, and reply in a dedicated thread view
- Search within a conversation
- Send messages and upload photos/files
- **Emoji reactions** — view, toggle, and add from a quick picker
- **Realtime updates** via Slack Socket Mode (`xapp-…`) or an external relay (SSE)
- Push notifications for new messages (in-app Socket Mode, or via your relay)
- Polling fallback when the live connection is down

## Requirements

- [Clickable](https://clickable-ut.dev/) 8.4.0+
- Ubuntu Touch device (or `clickable desktop` on Linux)
- A Slack app with **user** token scopes (see below)
- For Socket Mode: an **App-Level Token** (`xapp-…`) with `connections:write`

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
   | `channels:write` | Join public channels; mark public channels read |
   | `groups:write` | Mark private channels read |
   | `im:write` | Open DMs; mark DMs read |
   | `mpim:write` | Open group DMs; mark group DMs read |
   | `files:read` | Display images and file previews |
   | `files:write` | Upload photos and files |
   | `search:read` | Search messages within a conversation |
   | `reactions:write` | Add and remove emoji reactions |
   | `emoji:read` | Resolve workspace custom emoji for reactions |

3. Click **Install to Workspace** and allow access
4. Copy the **User OAuth Token** (`xoxp-…`) — not the bot token
5. Paste it into UTSlack’s Connect screen

### Socket Mode (recommended for live UI)

1. In your Slack app → **Basic Information** → **App-Level Tokens** → create a token with `connections:write` (`xapp-…`)
2. Enable **Socket Mode**
3. Under **Event Subscriptions**, turn on events and subscribe to these **on behalf of users** (not bot events):

   | Event | Purpose |
   |-------|---------|
   | `message.channels` | Messages in public channels |
   | `message.groups` | Messages in private channels |
   | `message.im` | Direct messages |
   | `message.mpim` | Group DMs |

4. In UTSlack → **Settings** → set realtime source to **In-app (Slack Socket Mode)** and paste the `xapp-` token

Creating or rotating an **App-Level Token** does **not** require reinstalling the app to the workspace (that prompt is for OAuth scope changes on user/bot tokens).

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

## Notifications & realtime

UTSlack registers with **UBports Push**. Choose a realtime source in **Settings**:

| Mode | Live UI | Pushes |
|------|---------|--------|
| **In-app Socket Mode** | Slack WebSocket | App sends to `push.ubports.com` while running |
| **External relay (SSE)** | App opens SSE to your relay URL | Relay sends pushes; app does not |

- Device must be signed in to an **OpenStore / UBports** account (PushClient auth)
- Popups may be suppressed while UTSlack is in the foreground (platform behavior)
- When the live path is down, chat/notify **polling** is used as fallback
- If the app was closed, opening a conversation loads history from Slack (normal catch-up)

### External relay contract (not shipped)

Your relay must be **reachable** from the phone (VPS, Tailscale, tunnel — not a plain NAT desktop with no path).

- Own Slack’s event stream (HTTP Events API or Socket Mode on the relay only — do not also run Socket Mode in the app)
- Expose an SSE endpoint the app `GET`s with `Accept: text/event-stream`
- Stream JSON events, for example:

```text
data: {"type":"message","channelId":"C123","user":"U456","text":"hello","ts":"1710000000.000100"}

```

- Send UBports Push with deep link `utslack://open?channel=…` and prefer notification tag `channelId:ts` for dedupe
- The app does not call `sendPush` in relay mode

## Project layout

```
qml/
  Main.qml                 # Auth gate, PageStack, PushClient, realtime, API façade
  AppTheme.qml             # Adaptive light/dark brand + bubble colors
  pages/                   # Login, conversations, chat, thread, settings, share target
  components/              # List/message/composer widgets
  js/
    SlackClient.js         # Slack Web API + pagination / 429 backoff
    SocketMode.js          # Socket Mode protocol helpers
    RelaySse.js            # Relay SSE event parsing
    Models.js              # Normalize API payloads for the UI
    Storage.js             # Persist tokens + notification / realtime prefs
    Notify.js              # Notify helpers + UBports Push sender
src/
  realtimesocket.*         # QWebSocket wrapper (Socket Mode)
  realtimesse.*            # SSE client (relay)
push/
  pushexec                 # Push helper (passthrough)
  push-helper.json
  push-apparmor.json
assets/logo.svg
utslack-contenthub.json    # Content Hub share destination (links, media, …)
```

## Privacy

Your tokens are stored only on-device in the app’s LocalStorage database. Logging out clears the user token and app-level token. The app talks to `https://slack.com/api/`, Slack Socket Mode WSS (when configured), your relay SSE URL (when configured), and `https://push.ubports.com/notify`.

## Share from other apps

UTSlack registers as a Content Hub share target for **links**, text, pictures, documents, and videos. From another app’s share menu, choose UTSlack, pick a channel or DM, and the link/file is posted there.

## Not in v1

Background daemon when fully suspended without a relay, embedding OAuth (bring-your-own Client ID), and a bundled relay server are out of scope for this release.

## License

MIT License.
