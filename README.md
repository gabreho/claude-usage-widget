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

- Build status: `swift build` passes.
- Issue tracker (`bd status`) snapshot:
  - Total issues: `18`
  - Open: `17`
  - Closed: `1`
  - Ready to work: `8`
- Latest completed item: color-coded status bar text (`claude-usage-am2`).
- Highest-priority open work:
  - `claude-usage-0hd`: OAuth token auto-refresh
  - `claude-usage-1bx`: In-app OAuth login via `WKWebView`
  - `claude-usage-qjp`: Auth path routing (depends on the two items above)

## Requirements

- macOS `13+`
- Xcode/Swift toolchain compatible with Swift `5.9`
- Claude CLI authenticated on this machine

## Quick Start

```bash
# 1) Authenticate Claude CLI (if not already authenticated)
claude auth login

# 2) Build
swift build

# 3) Run
swift run ClaudeUsage
```

After launch, the app appears in the menu bar as a gauge icon plus percentage.

## Authentication and Data Source

- Access token source: macOS Keychain service `Claude Code-credentials`
- Expected token shape: JSON containing `claudeAiOauth.accessToken`
- API endpoint: `https://api.anthropic.com/api/oauth/usage`
- Request headers include:
  - `Authorization: Bearer <token>`
  - `anthropic-beta: oauth-2025-04-20`

On `401`, the app surfaces a refresh hint (`claude auth login`).

## Project Structure

- `Package.swift`: SwiftPM executable target (`ClaudeUsage`, macOS 13+)
- `Sources/ClaudeUsage/ClaudeUsageApp.swift`: app entry + menu bar scene
- `Sources/ClaudeUsage/UsageViewModel.swift`: state, refresh loop, menu bar label/icon
- `Sources/ClaudeUsage/UsageService.swift`: keychain read + API client + error mapping
- `Sources/ClaudeUsage/UsageModels.swift`: API response models + utilization tiers
- `Sources/ClaudeUsage/UsagePopoverView.swift`: popover UI and progress rows

## Known Gaps

- No automated tests yet.
- No in-app OAuth flow yet (depends on roadmap items above).
- No threshold notifications yet.
- SPM executable today; Xcode app bundle migration is still open (`claude-usage-rff`).

## Issue Tracking Workflow

This repo uses `bd` (beads):

```bash
bd ready
bd show <id>
bd update <id> --status in_progress
bd close <id>
bd sync
```
