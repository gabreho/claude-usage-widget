# Claude Usage

Small macOS menu bar app that shows your Claude usage limits in near real time.

## What It Does

- Runs as a `MenuBarExtra` app (no Dock icon).
- Fetches usage from Anthropic's OAuth usage endpoint.
- Shows:
  - Session utilization (5-hour window)
  - Weekly utilization (7-day window)
  - Optional Opus/Sonnet 7-day buckets when present
- Uses color tiers for quick scanning:
  - Green: `< 50%`
  - Yellow: `50-79%`
  - Red: `>= 80%`
- Auto-refreshes every 5 minutes, with manual refresh in the popover.

## Current Status (Feb 15, 2026)

- Build status: `xcodebuild -project ClaudeUsage.xcodeproj -scheme ClaudeUsage -configuration Debug -derivedDataPath .build/DerivedData build` passes.
- Issue tracker (`bd status`) snapshot:
  - Total issues: `18`
  - Open: `16`
  - Closed: `2`
  - Ready to work: `9`
- Latest completed item: Xcode app bundle migration (`claude-usage-rff`).
- Highest-priority open work:
  - `claude-usage-0hd`: OAuth token auto-refresh
  - `claude-usage-1bx`: In-app OAuth login via `WKWebView`
  - `claude-usage-qjp`: Auth path routing (depends on the two items above)

## Requirements

- macOS `14+`
- Xcode with Swift toolchain support
- Claude CLI authenticated on this machine

## Quick Start

```bash
# 1) Authenticate Claude CLI (if not already authenticated)
claude auth login

# 2) Open the app project
open ClaudeUsage.xcodeproj
```

Then in Xcode:

1. Select the `ClaudeUsage` scheme
2. Choose `My Mac` destination
3. Press Run

If Xcode asks for signing settings, open target settings and pick your development team under `Signing & Capabilities` (automatic signing is enabled).

After launch, it appears in the menu bar as a gauge icon plus percentage.

## Authentication and Data Source

- Access token source:
  - Existing Claude CLI credentials in macOS Keychain service `Claude Code-credentials`
  - In-app OAuth login flow (`WKWebView` + PKCE) when credentials are missing/invalid
- Expected token shape in keychain JSON: `claudeAiOauth.accessToken` (plus refresh token + expiry)
- API endpoint: `https://api.anthropic.com/api/oauth/usage`
- Request headers include:
  - `Authorization: Bearer <token>`
  - `anthropic-beta: oauth-2025-04-20`

OAuth login bootstrap flow:
- Authorize URL: `https://claude.ai/oauth/authorize`
- Callback URL: `https://platform.claude.com/oauth/code/callback`
- Token endpoint: `https://platform.claude.com/v1/oauth/token`

## iOS Token Bootstrap Strategy

- Decision: use full in-app OAuth (webview-based) bootstrap on iOS.
- Rationale and alternatives: `docs/ios-token-strategy.md`.

## Project Structure

- `ClaudeUsage.xcodeproj`: native macOS app project
- `ClaudeUsageKit/`: local Swift package shared by app and widget targets
- `ClaudeUsageKit/Sources/ClaudeUsageKit/UsageModels.swift`: usage API models and tiers
- `ClaudeUsageKit/Sources/ClaudeUsageKit/UsageService.swift`: keychain read + API client + error mapping
- `ClaudeUsage/Info.plist`: app metadata (`LSUIElement=YES`)
- `Sources/ClaudeUsage/ClaudeUsageApp.swift`: app entry + menu bar scene
- `Sources/ClaudeUsage/UsageViewModel.swift`: state, refresh loop, menu bar label/icon
- `Sources/ClaudeUsage/UsagePopoverView.swift`: popover UI and progress rows
- `Sources/Shared/OAuthLoginView.swift`: shared in-app OAuth login view + `WKWebView` callback capture
- `Sources/ClaudeUsageiOS/`: iOS host app scaffold
- `Sources/ClaudeUsageWidget/`: iOS widget extension scaffold
- `ClaudeUsageiOS/Info.plist`: iOS host app metadata
- `ClaudeUsageWidget/Info.plist`: widget extension metadata
- `docs/ios-token-strategy.md`: iOS OAuth bootstrap decision record

## Known Gaps

- No automated tests yet.
- No threshold notifications yet.

## Issue Tracking Workflow

This repo uses `bd` (beads):

```bash
bd ready
bd show <id>
bd update <id> --status in_progress
bd close <id>
bd sync
```
