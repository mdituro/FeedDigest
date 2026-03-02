# FeedDigest

A native iOS app that fetches your Mastodon and Bluesky timelines and uses Apple Intelligence to produce a unified, readable digest of what you missed.

![iOS 26+](https://img.shields.io/badge/iOS-26%2B-black) ![Swift](https://img.shields.io/badge/Swift-5.0-orange) ![Apple Intelligence](https://img.shields.io/badge/Apple%20Intelligence-required-blue)

## Features

- **Unified timeline** — pulls posts from Mastodon and Bluesky into a single digest
- **Two summary styles** — Thematic (narrative prose grouped by topic) or Bullet (one point per event)
- **On-device AI** — summarization runs entirely on-device via Foundation Models; no data leaves your phone
- **Media display** — view attached images inline or as links
- **Mastodon OAuth** — connects via standard OAuth 2.0 / ASWebAuthenticationSession
- **Bluesky app passwords** — authenticates via AT Protocol with automatic JWT refresh
- **Multiple accounts** — add as many Mastodon and Bluesky accounts as you like

## Requirements

- iOS 26 or later
- Apple Intelligence enabled (Settings → Apple Intelligence & Siri)
- iPhone 15 Pro / iPhone 16 or later, or any M-series iPad (required for on-device model)
- Xcode 26+ to build

## Getting Started

1. Clone the repo
   ```bash
   git clone https://github.com/mdituro/FeedDigest.git
   cd FeedDigest
   ```

2. Open the project
   ```bash
   open FeedDigest.xcodeproj
   ```

3. In Xcode, set your **Development Team** under Target → Signing & Capabilities

4. Build and run on a device or simulator with Apple Intelligence enabled

## Adding Accounts

**Mastodon**
1. Go to the Accounts tab → **+** → Mastodon
2. Enter your instance domain (e.g. `mastodon.social`)
3. Complete the OAuth flow in the browser sheet that appears

**Bluesky**
1. Go to the Accounts tab → **+** → Bluesky
2. Enter your handle and an **App Password** (not your main password)
   - Generate one at bsky.app → Settings → App Passwords

## Project Structure

```
FeedDigest/
├── FeedDigestApp.swift          # App entry point, URL scheme handler
├── ContentView.swift            # TabView root
├── Models/
│   ├── Post.swift               # Unified Post model
│   ├── Account.swift            # SocialAccount, MastodonAppRegistration
│   ├── Summary.swift            # DigestSummary, sections, bullets, media
│   └── AppSettings.swift        # MediaDisplayMode, SummaryStyle
├── Services/
│   ├── KeychainService.swift    # Keychain read/write/delete
│   ├── MastodonService.swift    # OAuth flow, timeline fetch, HTML stripping
│   ├── BlueskyService.swift     # AT Protocol auth, timeline fetch
│   └── SummarizationService.swift  # Foundation Models + @Generable output types
├── ViewModels/
│   └── AppState.swift           # @Observable state, orchestrates fetch & summarize
└── Views/
    ├── SummaryView.swift
    ├── AccountsView.swift
    ├── AddMastodonAccountView.swift
    ├── AddBlueskyAccountView.swift
    └── SettingsView.swift
```

## How Summarization Works

FeedDigest uses Foundation Models' `@Generable` structured output API — no post content is sent to any server. The on-device model receives up to 40 recent posts and fills in typed Swift structs directly, guided by `@Guide` descriptions that instruct it to aggregate posts covering the same topic and name specific people, products, and events rather than producing vague category summaries.

If the model's guardrails are triggered by timeline content, the app automatically retries with a metadata-only prompt (handles, timestamps, URLs — no post text).

## Settings

| Setting | Options |
|---|---|
| Summary Style | Thematic · Bullet |
| Media Display | Inline · Links Only |
| Last Checked | Shows last fetch time; reset to re-digest older posts |

## License

MIT
