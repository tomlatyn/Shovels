# Shovels

A macOS menu bar app that shows your usage limits for Claude Code, Codex, Antigravity and Cursor in a retro CRT-style dashboard.

Shovels runs each tool's own command line program in the background, reads the usage numbers it reports, and shows them as bars with reset countdowns. It can warn you when a limit gets close, estimate when you will run out at your current pace, and draw a small history line for each window. It is a personal-use app: native SwiftUI, not sandboxed, not notarized.

## Features

- One card per provider, with each limit window, its percentage, a reset countdown and the plan name.
- The menu bar shows one provider's glyph and percentage. You choose which provider.
- Alerts at 80% and 95%, and when a nearly full window resets.
- Burn-rate runway: "At this pace: full in …" when a window would fill before it resets.
- Show or hide providers, open at login, and a test alert, all in Settings.
- Phosphor theme: a black ground, phosphor-green text, a 20-cell bar per window that turns red at 90% or more, and the bundled VT323 and Press Start 2P fonts.

## Providers

Each visible provider is checked when the app starts, every five minutes, ten seconds after the Mac wakes, and when you click REFRESH. Hidden providers aren't checked.

- When a check times out or a service is down, Shovels retries that provider after one, two and four minutes, then goes back to the regular schedule.
- A setup problem, such as a missing CLI or a sign-in, waits for the next regular check or REFRESH.
- A check that takes longer than 90 seconds is abandoned and its CLI is stopped, so one stuck tool can't hold up the others.
- Each CLI runs in its own process group. When a check ends, or Shovels quits, the CLI and anything it started are stopped.

### Claude Code

- Runs `claude -p /usage --no-session-persistence --strict-mcp-config` and reads the session (5-hour) and weekly (all models) percentages and reset times. The two flags keep the checks out of `claude --resume` and skip starting MCP servers. Older Claude Code versions that don't know them are run without them.
- Reads the plan from `claude auth status --json`. Only the `subscriptionType` field is used.
- Totals input and output tokens over the last five hours from `~/.claude/projects/**/*.jsonl`. Only files changed in the last five hours are read, and only the last 32 MB of each.

### Codex

- Runs `codex app-server`, sends a JSON-RPC `initialize`, then `account/rateLimits/read`.
- Shows each window the reply contains (for example Monthly) and the plan type.

### Antigravity

- Runs `agy` in a pseudo-terminal in its own empty folder, `~/Library/Application Support/Shovels/antigravity-workspace`, waits for its prompt, types `/usage`, and reads the Models & Quota panel.
- The panel has a quota group per model family, such as GEMINI and CLAUDE AND GPT. Each group has a Five Hour and a Weekly limit, and the card shows them under a heading per group.
- The panel reports what is left, so used is 100 minus remaining. A full window says "Quota available" and has no reset time.
- The plan comes from `(Google AI <plan>)` next to your account, when it appears.
- You must trust the folder once in Terminal. See [Setting up Antigravity](#setting-up-antigravity).
- Each check takes about 15 seconds. agy records each `/usage` in its own command history.

### Cursor

- Runs `agent` in its own empty folder, `~/Library/Application Support/Shovels/cursor-workspace`, waits for its prompt, types `/usage`, and reads the Included, Auto and API percentages, the plan, and the monthly reset date.
- You must trust that folder once in Terminal. See [Setting up Cursor](#setting-up-cursor).
- When Cursor's usage service fails to load data, the card shows a plain outage message instead of setup steps.

### Prompts Shovels never answers

Shovels types into Antigravity and Cursor only after their normal prompt is on screen. If a CLI shows a trust question or a sign-in screen, or never reaches its prompt, Shovels presses Ctrl-C, types nothing else, and the card tells you what to run in Terminal.

## Using Shovels

- **Menu bar.** Shows the chosen provider's glyph and the percentage of its first window: Session for Claude Code, the first group's Session for Antigravity, the first window Codex returns, and Included for Cursor. It shows `?` when there is no fresh reading, including when a window's reset time has passed. The item is a monochrome template, so it follows light and dark menu bars. If the chosen provider is hidden, the first visible one is used. There is no Dock icon. Hover over it to see each provider's status.
- **Dashboard.** Click the menu bar item to open it. A card loses its provider color once one of its windows has reset, until a new reading arrives. A provider that is not connected yet shows its setup steps in place of its card. A provider that timed out or is down shows a short message in gray and keeps its last reading.
- **Settings.**
  - SHOW: turn each provider ON or OFF.
  - MENU BAR SHOWS: pick the menu bar provider.
  - ALERTS: on or off, plus TEST ALERT.
  - OPEN AT LOGIN: uses `SMAppService`. If macOS asks for approval, Shovels opens Login Items in System Settings.

## Alerts

- Thresholds are 80% and 95%. Each threshold alerts once per window cycle. A jump past both sends one alert.
- A notification names the provider, the quota group when there is one, and the window. It gives the percentage and the time until reset, and adds the pace estimate when the window would fill before it resets.
- A reset alert is sent when a window that was at 99% or more resets.
- Alerts are on by default and need a known reset time. Shovels asks for notification permission at launch.

## Runway

- Runway appears only when the window would fill before it resets.
  - Windows of five hours or less use the pace of the last 30 minutes. They need at least 10 minutes of readings, and usage must be rising.
  - Longer windows, such as weekly and monthly, use the average pace since the cycle began, starting one hour in. A short burst can't last for days, because the 5-hour limit stops it first.
  - Cursor's windows have no stated length, so they get no runway.
- Readings are stored in `~/Library/Application Support/Shovels/history.json` and kept for 24 hours. They are never sent anywhere.

## Privacy

- Shovels makes no network calls of its own.
- The vendor CLIs contact their own services using your existing logins.
- Shovels never reads or stores login tokens. From `claude auth status --json` it reads only `subscriptionType`.
- The Claude Code logs are read locally. Only token counts from each message's `usage` field are kept, counted once per message.
- To find the CLIs, Shovels asks your login shell for its `PATH` once per launch (and again on REFRESH). Nothing else from your shell is kept.
- Preferences are stored in `UserDefaults`: hidden providers, the menu bar provider, alerts on or off, which alerts were already sent, and any CLI paths you set.

## Requirements

- macOS 14 or later.
- Xcode to build from source (built with Xcode 27).
- Each CLI you want to track, installed and signed in: `claude`, `codex`, `agy`, `agent`.

### How Shovels finds the CLIs

1. A path you set with `defaults write com.tomaslatyn.shovels cliPath.<name> /full/path`, for example `cliPath.claude`.
2. Your login shell's `PATH`, so a CLI that works in Terminal (Homebrew, nvm, Volta, Bun, `~/.local/bin`) is found.
3. These folders: `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, `~/.claude/local`, `~/.npm-global/bin`, `~/.bun/bin`, `~/.volta/bin`.

The CLIs run with a `PATH` that starts with their own folder, then your shell's `PATH`, so a CLI that needs `node` finds the same one Terminal does.

To remove a path you set:

```bash
defaults delete com.tomaslatyn.shovels cliPath.claude
```

## Build from source

```bash
cd Limits   # the folder that contains Shovels.xcodeproj
xcodebuild -project Shovels.xcodeproj -scheme Shovels -configuration Release \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
open build/Build/Products/Release/Shovels.app
```

For a signed build, set your team under Signing & Capabilities in Xcode.

Run the tests:

```bash
xcodebuild -project Shovels.xcodeproj -scheme Shovels -derivedDataPath build CODE_SIGNING_ALLOWED=NO test
```

The tests check each provider's parser against real CLI output in `ShovelsTests/Fixtures.swift`, plus the alert and history rules. When a vendor changes its `/usage` screen, capture the new output, add it there, and fix the parser until the tests pass.

## Running a build on another Mac

No prebuilt downloads are published yet. Builds are not notarized, so if you copy one to another Mac, macOS blocks the first launch. Open System Settings > Privacy & Security and choose **Open Anyway**, or remove the quarantine flag:

```bash
xattr -dr com.apple.quarantine /Applications/Shovels.app
```

## Setting up Antigravity

Trust the workspace folder once. Shovels also creates the folder on its first Antigravity check.

```bash
mkdir -p ~/Library/Application\ Support/Shovels/antigravity-workspace
cd ~/Library/Application\ Support/Shovels/antigravity-workspace
agy   # sign in if asked, choose "Yes, I trust this folder", then quit
```

Click REFRESH in Shovels afterwards.

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

- **A card says it couldn't find a CLI.** Check that the CLI runs in a new Terminal window. If it's installed somewhere your shell doesn't know about, set its path as shown under [How Shovels finds the CLIs](#how-shovels-finds-the-clis), then click REFRESH.
- **A card says a CLI didn't reach its prompt.** Run that CLI in Terminal from the folder named in the message, sign in or answer its trust question, then click REFRESH.
- **A card says you aren't signed in, or shows no usage.** Run the CLI in Terminal, sign in, then click REFRESH.
- **No notifications.** Allow Shovels in System Settings > Notifications, then click TEST ALERT in Settings.
- **No runway.** It only appears when a window would fill before it resets. A 5-hour window also needs 10 minutes of rising readings.

## Reporting a bug

Open an issue with:

- your macOS version and how you installed each CLI (Homebrew, npm, native installer);
- the message on the card, or the menu bar tooltip;
- for a parsing problem, what the CLI's `/usage` screen shows in Terminal. Remove your email and any other account details first.

## Uninstall

1. Turn OPEN AT LOGIN off in Settings, then quit Shovels.
2. Delete `Shovels.app`.
3. Remove its data and preferences:

```bash
rm -rf ~/Library/Application\ Support/Shovels
```

```bash
defaults delete com.tomaslatyn.shovels
```

If you trusted the workspace folders in Antigravity or Cursor, you can also remove them from those tools' trusted folder lists.

## What a check costs

Every five minutes Shovels starts up to four CLIs: `claude` twice (usage and plan), `codex app-server` for a moment, and `agy` and `agent` for about 15 seconds each in a hidden terminal. Shovels only opens their usage screens and never sends a prompt. If you only care about some providers, hide the others in Settings, and they won't be started.

## Limitations

- Cursor and Antigravity are read from their CLIs' interactive `/usage` screens. A change to those screens can break them. The tests make that quick to spot and fix.
- Cursor and Antigravity need a one-time trust step.
- The Antigravity plan comes from the text next to your account and may differ from your account page.
- Claude Code and Codex show only what their CLIs report.
- The menu bar item is monochrome by design. Provider colors appear only in the dashboard.
- Shovels is for personal use. It is not sandboxed and not notarized.

## Project layout

```text
Shovels/
├── App/          App entry point and the MenuBarExtra scene
├── Models/       Provider IDs, usage windows, snapshots, and the provider error protocol
├── Providers/    One reader per provider: Claude Code, Codex, Antigravity, Cursor
├── Services/     Process and pseudo-terminal runners, CLI lookup, alerts, history, launch at login, fonts, paths
├── Store/        UsageStore: refresh schedule, retries, deadlines, settings
├── Views/        Dashboard, setup cards, menu bar label, glyphs, palette
└── Resources/    Bundled VT323 and Press Start 2P fonts
ShovelsTests/     Parser tests against captured CLI output, and alert and history rules
```

## License

MIT. See [LICENSE](LICENSE).

VT323 and Press Start 2P are bundled under the SIL Open Font License. Their licenses are in [licenses/](licenses/).

The provider marks are original pixel drawings, not official logos.
