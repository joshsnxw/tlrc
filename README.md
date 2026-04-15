# Juice

A lightweight macOS menu bar app that monitors your battery and blocks your screen when it drops below a threshold — until you plug in.

## Requirements

- macOS 13 Ventura or later
- Xcode Command Line Tools (`xcode-select --install`)

## Build & Run

```bash
make open
```

Or install to `/Applications`:

```bash
make install
```

## Usage

**Menu bar icon** reflects battery level at a glance:
- `drop.fill` — above 10%
- `drop.halffull` — at or below 10%

**Click the icon** to open the menu:
- Current battery percentage and power status
- **Alert threshold** slider — set the level that triggers the overlay (1–10%, default 5%)
- **Launch at Login** toggle
- Quit

**Overlay** — when the battery hits your threshold while unplugged, a full overlay appears in the center of your screen. It stays there until you plug in. No dismiss button.

## Notes

- No special permissions required. IOKit battery access is available to all user-space apps.
- Charger plug/unplug is detected instantly via an IOKit run loop notification — no polling lag.
- Polling intervals adapt to battery level: every 30 min above 50%, 15 min from 20–50%, 5 min from 10–20%, 30 sec below 10%.
- Launch at Login is managed through `SMAppService` — toggling it registers or unregisters the app directly in System Settings → General → Login Items.
