# Runway

A macOS menu bar app that shows how much room is left in your Claude Code limits, in a retro CRT-style dashboard.

The MVP tracks Claude Code only. It shows the 5-hour and weekly windows, and the input and output tokens from the last five hours. Codex, alerts, and API spend come later. See [PLAN.md](PLAN.md) for the full plan.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 16 or later (built with Xcode 27)
- Claude Code, signed in

## Build from source

```bash
cd Limits   # the folder containing Runway.xcodeproj
xcodebuild -project Runway.xcodeproj -scheme Runway -configuration Release \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
open build/Build/Products/Release/Runway.app
```

A locally built app isn't quarantined, so macOS opens it without a warning.

Signing is optional for personal use. To sign with your own team, set it under Signing & Capabilities in Xcode.

## First launch

1. Runway appears in the menu bar as `CC` with a percentage. Click it to open the dashboard.
2. If limits are unavailable, click **ENABLE LIMITS**. Runway shows the exact change to `~/.claude/settings.json` before writing anything, and backs up your current file to `~/Library/Application Support/Runway/settings-backup.json`.
3. Send one message in Claude Code. The limits appear after the first response.

If you already have a status line, Runway leaves it alone. The card then says so.

## Downloaded builds

A release zip isn't notarized, so macOS blocks the first launch. Open System Settings › Privacy & Security and choose **Open Anyway**. Or remove the quarantine flag in Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/Runway.app
```

## What Runway reads

- `~/Library/Application Support/Runway/claude-limits.json`, written by the status line helper Runway installs.
- `~/.claude/projects/**/*.jsonl`, to total input and output tokens over the last five hours.

Nothing leaves your Mac. Runway makes no network calls.

## Fonts

Press Start 2P and VT323 are bundled under the SIL Open Font License. The licenses are in [licenses/](licenses/).

## License

MIT. See [LICENSE](LICENSE).
