# iOS Token Bootstrap Strategy

Date: 2026-02-15
Issue: `claude-usage-rah`

## Decision

Use a full in-app OAuth flow (embedded webview) on iOS as the token bootstrap strategy.

## Why

- Works consistently across all iOS installs without relying on desktop-side state.
- Avoids assumptions about iCloud Keychain sync timing and account configuration.
- Avoids one-time transfer UX and security complexity (QR, paste, local transport).
- Keeps token lifecycle aligned with OAuth refresh rotation already implemented in app logic.

## Alternatives considered

- iCloud Keychain sync from macOS credentials: rejected for reliability and observability concerns.
- One-time token transfer from macOS: rejected due to operational overhead and support burden.
