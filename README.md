# Shovels

A macOS menu bar app that shows your usage limits for Claude Code, Codex, Antigravity and Cursor in a retro CRT-style dashboard.

Shovels runs each tool's own command line program in the background, reads the usage numbers it reports, and shows them as bars with reset countdowns. It can warn you when a limit gets close, estimate when you will run out at your current pace, and draw a small history line for each window. It is a personal-use app: native SwiftUI, not sandboxed, not notarized.

## Screenshots

Screenshots will be added.

## Features

- One card per provider, with each limit window, its percentage, a reset countdown and the plan name.
- The menu bar shows one provider's glyph and percentage. You choose which provider.
- Alerts at 80% and 95%, and when a nearly full window resets.
- Burn-rate runway: "At this pace: full in …" when a window would fill before it resets.
- Sparklines of each window's usage during the current cycle.
- Show or hide providers, open at login, and a test alert, all in Settings.
- Phosphor theme: a black ground, phosphor-green text, a 20-cell bar per window that turns red at 90% or more, and the bundled VT323 and Press Start 2P fonts.

## Providers

All four providers are checked when the app starts, every five minutes, and when you click REFRESH. If a provider was working and then fails, Shovels checks again after one minute. A provider that has not worked yet, for example because its CLI is missing, waits for the next regular check.

### Claude Code

- Runs `claude -p /usage` and reads the session (5-hour) and weekly (all models) percentages and reset times.
- Reads the plan from `claude auth status --json`. Only the `subscriptionType` field is used.
- Totals input and output tokens over the last five hours from `~/.claude/projects/**/*.jsonl`. Only files changed in the last five hours are read, and only the last 32 MB of each.

### Codex

- Runs `codex app-server`, sends a JSON-RPC `initialize`, then `account/rateLimits/read`.
- Shows each window the reply contains (for example Monthly) and the plan type.

### Antigravity

- Runs `agy` in a pseudo-terminal, types `/usage`, and reads "Five Hour Limit Remaining" and "Weekly Limit Remaining" with their refresh times.
- The panel reports what is left, so used is 100 minus remaining.
- The plan comes from `(Google AI <plan>)` text in the command menu, when it appears.
- Each check takes about 20 seconds.

### Cursor

- Runs `agent` in its own empty folder, `~/Library/Application Support/Shovels/cursor-workspace`, types `/usage`, and reads the Included, Auto and API percentages, the plan, and the monthly reset date.
- You must trust that folder once in Terminal. Shovels never answers a trust prompt; if one appears, it stops and the card tells you what to do.
- When Cursor's usage service fails to load data, the card shows a plain outage message instead of setup steps.

## Using Shovels

- **Menu bar.** Shows the chosen provider's glyph and the percentage of its first window: Session for Claude Code and Antigravity, the first window Codex returns, and Included for Cursor. It shows `?` when there is no fresh reading, including when a window's reset time has passed. The item is a monochrome template, so it follows light and dark menu bars. If the chosen provider is hidden, the first visible one is used. There is no Dock icon.
- **Dashboard.** Click the menu bar item to open it. A card loses its provider color once one of its windows has reset, until a new reading arrives. A provider that is not connected yet shows its setup steps in place of its card.
- **Settings.**
  - SHOW: turn each provider ON or OFF.
  - MENU BAR SHOWS: pick the menu bar provider.
  - ALERTS: on or off, plus TEST ALERT.
  - OPEN AT LOGIN: uses `SMAppService`.

## Alerts

- Thresholds are 80% and 95%. Each threshold alerts once per window cycle. A jump past both sends one alert.
- A notification names the provider and window, gives the percentage and the time until reset, and adds the pace estimate when the window would fill before it resets.
- A reset alert is sent when a window that was at 99% or more resets.
- Alerts are on by default and need a known reset time. Shovels asks for notification permission at launch.

## Runway and sparklines

- Runway uses the pace of the last 30 minutes. It appears only when usage is rising, there are at least 10 minutes of readings, and the window would fill before it resets.
- A sparkline appears after at least three readings spanning 10 minutes or more in the current window cycle.
- Readings are stored in `~/Library/Application Support/Shovels/history.json` and kept for 24 hours. They are never sent anywhere.

## Privacy

- Shovels makes no network calls of its own.
- The vendor CLIs contact their own services using your existing logins.
- Shovels never reads or stores login tokens. From `claude auth status --json` it reads only `subscriptionType`.
- The Claude Code logs are read locally. Only token counts from each message's `usage` field are kept, counted once per message.
- Preferences are stored in `UserDefaults`: hidden providers, the menu bar provider, alerts on or off, and which alerts were already sent.

## Requirements

- macOS 14 or later.
- Xcode to build from source (built with Xcode 27).
- Each CLI you want to track, installed and signed in: `claude`, `codex`, `agy`, `agent`.
- Shovels looks for the CLIs only in these places:
  - `claude`, `codex`, `agy`: `/opt/homebrew/bin` or `/usr/local/bin`
  - `agent`: `~/.local/bin`, `/opt/homebrew/bin` or `/usr/local/bin`
- The CLIs run with `PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin`. A CLI that needs Node.js needs `node` on one of those paths.

## Build from source

```bash
cd Limits   # the folder that contains Shovels.xcodeproj
xcodebuild -project Shovels.xcodeproj -scheme Shovels -configuration Release \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
open build/Build/Products/Release/Shovels.app
```

For a signed build, set your team under Signing & Capabilities in Xcode.

## Downloaded builds

Builds are not notarized, so macOS blocks the first launch. Open System Settings > Privacy & Security and choose **Open Anyway**, or remove the quarantine flag:

```bash
xattr -dr com.apple.quarantine /Applications/Shovels.app
```

## Setting up Cursor

Trust the workspace folder once. Shovels also creates the folder on its first Cursor check.

```bash
agent login
mkdir -p ~/Library/Application\ Support/Shovels/cursor-workspace
cd ~/Library/Application\ Support/Shovels/cursor-workspace
agent   # choose Trust when asked, then quit
```

Click REFRESH in Shovels afterwards.

## Troubleshooting

- **A card says a CLI isn't installed.** Check that it is in one of the paths under [Requirements](#requirements). A CLI installed elsewhere, such as `~/.local/bin/claude`, is not found.
- **A card says you aren't signed in, or shows no usage.** Run the CLI in Terminal, sign in, then click REFRESH.
- **No notifications.** Allow Shovels in System Settings > Notifications, then click TEST ALERT in Settings.
- **No runway or sparkline.** Both need at least 10 minutes of readings. Runway also needs usage to be rising.

## Limitations

- Cursor and Antigravity are read from their CLIs' interactive `/usage` screens. A change to those screens can break them.
- Cursor needs a one-time trust step.
- The Antigravity plan comes from the command menu text and may differ from your account.
- Claude Code and Codex show only what their CLIs report.
- CLIs are found only in the fixed paths listed under Requirements.
- The menu bar item is monochrome by design. Provider colors appear only in the dashboard.
- Shovels is for personal use. It is not sandboxed and not notarized.

## Project layout

```text
Shovels/
├── App/          App entry point and the MenuBarExtra scene
├── Models/       Provider IDs, usage windows and snapshots
├── Providers/    One reader per provider: Claude Code, Codex, Antigravity, Cursor
├── Services/     Alerts, history, pseudo-terminal runner, launch at login, fonts, paths
├── Store/        UsageStore: refresh schedule, retries, settings
├── Views/        Dashboard, setup cards, menu bar label, glyphs, sparkline, palette
└── Resources/    Bundled VT323 and Press Start 2P fonts
```

`PLAN.md` holds early design notes. Much of it is out of date.

## License

MIT. See [LICENSE](LICENSE).

VT323 and Press Start 2P are bundled under the SIL Open Font License. Their licenses are in [licenses/](licenses/).

The provider marks are original pixel drawings, not official logos.
