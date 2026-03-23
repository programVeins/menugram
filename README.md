# MenuGram

A lightweight macOS menu bar app for quick Telegram messaging — built for fast back-and-forth with AI agents like [OpenClaw](https://github.com/ArcadeLabsInc/openclaw), [PicoClaw](https://github.com/ArcadeLabsInc/picoclaw), and similar bots.

Lives in your menu bar, opens with a click, and gets out of your way.

## Features

- Menu bar app — no dock icon, always one click away
- Text and voice message support (record & send voice notes)
- Voice note playback with waveform visualization
- Live typing/recording indicators
- Auto-connects to your configured bot on launch

## Prerequisites

- macOS 15.0+
- Xcode 26+
- A Telegram account
- A Telegram API ID & Hash (free, from [my.telegram.org](https://my.telegram.org))
- A Telegram bot you want to chat with

## Setup

### 1. Get Telegram API Credentials

1. Go to [my.telegram.org](https://my.telegram.org) and log in
2. Click **API development tools**
3. Create a new application (any name/platform)
4. Note your **api_id** and **api_hash**

### 2. Configure Environment Variables in Xcode Scheme

1. Open `MenuGram.xcodeproj` in Xcode
2. Go to **Product > Scheme > Edit Scheme…** (or `Cmd+<`)
3. Select **Run** in the sidebar, then the **Arguments** tab
4. Under **Environment Variables**, add the following:

| Variable | Value | Description |
|----------|-------|-------------|
| `TELEGRAM_API_ID` | `12345678` | Your API ID from step 1 |
| `TELEGRAM_API_HASH` | `your_api_hash_here` | Your API hash from step 1 |
| `BOT_NAME` | `YourBotName` | Display name of the bot/contact to auto-open on launch |

`BOT_NAME` is the display name of the Telegram bot/contact you want MenuGram to auto-open on launch. For example, if your bot is called "PicoClaw", set `BOT_NAME=PicoClaw`.

### 3. Build & Run

1. Wait for Swift Package Manager to resolve dependencies (TDLibKit)
2. In Signing & Capabilities, enable **Audio Input** under App Sandbox
3. Build and run (`Cmd+R`)
4. Sign in with your phone number when prompted

## How It Works

MenuGram uses [TDLib](https://github.com/tdlib/td) (via [TDLibKit](https://github.com/Swiftgram/TDLibKit)) as the Telegram client library. It authenticates as a full Telegram user (not a bot), so you can send and receive messages just like the official app.

On launch, it searches your chat list for the bot name specified in `BOT_NAME` and opens that conversation automatically. You can send text or voice messages, and see real-time typing indicators from the other side.

## Project Structure

```
MenuGram/
├── Constants.swift              # App config, reads env vars from scheme
├── Models/
│   ├── ChatItem.swift           # Chat list model
│   └── MessageItem.swift        # Message model
├── Services/
│   ├── TelegramService.swift    # TDLib client wrapper
│   └── OGGOpusConverter.swift   # OGG Opus to WAV conversion
└── Views/
    ├── RootView.swift           # Top-level navigation
    ├── Auth/                    # Login flow (phone, code, password)
    └── Chat/
        ├── ChatDetailView.swift     # Message list + header
        ├── MessageBubbleView.swift  # Individual message bubbles
        ├── MessageInputView.swift   # Text + voice input
        └── VoiceNoteView.swift      # Voice message playback
```

## License

MIT
