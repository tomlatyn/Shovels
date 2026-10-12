# Shovels

A macOS menu bar app that shows your Claude Code and Codex limits in a retro CRT-style dashboard.

- **Claude Code:** session and weekly limits, your plan (such as PRO), and input and output tokens from the last five hours.
- **Codex:** the limit window for your account and plan.
- **Not connected yet:** Cursor and Antigravity. Click GUIDES in the app to see what each one needs.

See [PLAN.md](PLAN.md) for the full plan.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode, to build from source (built with Xcode 27)
- Claude Code and the Codex CLI, each signed in

## Build from source

```bash
cd Limits   # the folder containing Shovels.xcodeproj
xcodebuild -project Shovels.xcodeproj -scheme Shovels -configuration Release \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
open build/Build/Products/Release/Shovels.app
```

A locally built app isn't quarantined, so macOS opens it without a warning.

Signing is optional for personal use. To sign with your own team, set it under Signing & Capabilities in Xcode.

## First launch

1. Shovels appears in the menu bar: a shovel, then Claude Code's session percentage and Codex's. Click it to open the dashboard.
2. The numbers appear after the first check, which takes a few seconds.
3. Click **GUIDES** for how to sign in to each tool.

## Downloaded builds

A release zip isn't notarized, so macOS blocks the first launch. Open System Settings › Privacy & Security and choose **Open Anyway**. Or remove the quarantine flag in Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/Shovels.app
```

## What Shovels reads

- `claude -p /usage` and `claude auth status --json`, from the Claude Code CLI using your existing login. Only the plan field is read from the auth output.
- `codex app-server`, asked for the account's rate limits, from the Codex CLI using your existing login.
- `~/.claude/projects/**/*.jsonl`, to total input and output tokens over the last five hours.

Shovels never reads or stores a login token. The CLIs contact their own services. Shovels makes no network calls of its own.

## Fonts

Press Start 2P and VT323 are bundled under the SIL Open Font License. The licenses are in [licenses/](licenses/).

## License

MIT. See [LICENSE](LICENSE).
