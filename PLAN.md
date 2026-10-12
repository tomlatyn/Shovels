# Phosphor: plan

A menu bar utility that tracks subscription usage and limits for Claude Code, Codex, Antigravity and Cursor, shown in a retro CRT-style dashboard.

Design mockup (canvas): https://claude.ai/artifact/CaPsAUSdq5wsAMGfGvAkEv (private; only the owner can open it until it is shared from the page's Share menu)

## 1. Name

| Name | Why | Note |
|---|---|---|
| **Phosphor** (recommended) | The green CRT phosphor glow ties to the retro theme. Short, and it reads as a "display" tool. | Not yet checked for App Store or trademark collisions. |
| Tally | Counts usage at a glance. | Common word, probably used by others. |
| Redline | Evokes limits and warnings. | Aggressive tone. |
| Quotabar | Describes exactly what it is. | Plain, less retro. |
| Ration | Fits the "limits" idea. | Slightly negative tone. |

Bundle ID: `com.<you>.phosphor` as a placeholder. Set it once the name and Apple developer account are settled.

## 2. Design direction: Phosphor theme

**Concept.** A black CRT with phosphor text, flat panels, pixel glyphs and a pixel display font. No glows, gradients or blur. Each provider gets its own accent color, so the dashboard is readable at a glance.

**Palette**

| Role | Hex | Use |
|---|---|---|
| Ground | `#0B0E0B` | Dashboard background |
| Panel | `#111612` | Dropdown panel and cards |
| Border | `#2A3A2C` | Hairlines, dividers |
| Phosphor text | `#B8F5C4` | Primary text |
| Secondary text | `#7FA286` | Labels, timestamps (about 6.7:1 on the panel) |
| Alert | `#FF5A4E` | Limits at 90% or more only |
| Claude Code | `#FFA640` | Amber |
| Codex | `#5BFF8A` | Phosphor green |
| Antigravity | `#FF5DCB` | Magenta |
| Cursor | `#4DE3FF` | Cyan |

**Type.** Press Start 2P for titles and labels (used sparingly). VT323 for numbers and body text. Both are SIL OFL, so they can be bundled. Check each license file when bundling.

**Pixel glyphs.** Drawn in-house on an 8×8 grid. They are generic signifiers, not provider logos.
- Claude Code: a cross-star spark
- Codex: a `>_` prompt
- Antigravity: a diamond
- Cursor: a pointer arrow

**Limit bars.** Ten-segment text bars (`█████░░░░░`) with a percentage. Below 80%: provider color. 80–89%: provider color, plus a `HIGH` tag. 90% or more: the bar turns alert red and shows `NEAR LIMIT`.

**Menu bar item (decision).** The real menu bar item is monochrome, using a template image and text such as `CC 47%`, so it works on both light and dark menu bars. Provider colors appear only in the dropdown. The mockup shows colored text in the bar; that is the one place it differs from the real build.

**States.** Every card is one of three states:
- **LIVE**: a fresh reading, with a reset countdown.
- **STALE**: the window has reset, or the snapshot is old. Shows the last value in secondary text with a hollow bar, plus an "as of" time. Old data is not an alert, so STALE never uses red.
- **NO SOURCE**: the provider needs setup.

**Themes (later).** Phosphor (default), Amber, Magenta, and Mono. These swap the palette only.

## 3. Features

**MVP**
- Menu bar item showing the pinned providers, with the tightest limit first.
- Dropdown dashboard with one card per provider: 5-hour and weekly windows, reset countdown, plan tag, source tag, and "as of" time.
- LIVE / STALE / NO SOURCE states.
- Sources screen: choose a data source per provider. Optional API-spend keys, stored in the Keychain.
- Notifications at 80% and 95%.
- Refresh on file change, a 60-second poll, and a manual refresh button.
- Launch at login (`SMAppService`).

**Later**
- Usage history sparklines, from snapshots stored in Application Support.
- Daily token totals from the Claude Code and Codex logs.
- Antigravity support once a source is confirmed.
- Themes.
- Optional CRT sound on threshold alerts.

## 4. Data sources (checked on this Mac)

The app cannot get subscription limits from API keys for most of these providers. Admin or usage keys report pay-as-you-go API spend only. So each provider gets a **source picker**, and an API key is one option among them.

| Provider | Source | What it gives | Status |
|---|---|---|---|
| **Codex** | `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`. Read the last `token_count` event. | `rate_limits.primary` (5-hour window, `window_minutes` 300) and `secondary` (weekly, 10080), each with `used_percent` and `resets_at` (Unix time). Also `plan_type` and credits. | **Confirmed.** The 30 newest rollout files all contain `rate_limits`. The newest file here is from 11 Sep 2026, so it is about a month old. That is why the STALE state matters. The desktop app folders (`~/Library/Application Support/Codex`, `com.openai.codex`) hold no rollouts or `rate_limits`, so `~/.codex` is the only source found. |
| **Claude Code** (tokens) | `~/.claude/projects/<project>/<session>.jsonl`, `message.usage` | Token counts per message: input, output, cache read and cache write. | **Confirmed** that the data is present. It gives token totals, not limit percentages. |
| **Claude Code** (limits) | The status line JSON, `rate_limits.five_hour` and `rate_limits.seven_day`, each with `used_percentage` and `resets_at`. The app reads it through a small helper script the user registers as the `statusLine` command. | Limit percentages and reset times. | **Needs verification.** Third-party guides and the Claude Code changelog (v2.1.80) describe the field. Some GitHub reports say it is missing for Max users, and the field appears only after a session's first response. Test it on this Mac before building on it. Setup edits `~/.claude/settings.json`, so it must be opt-in. |
| **Cursor** (plan) | `state.vscdb` keys `cursorAuth/stripeMembershipType` and `cursorAuth/stripeSubscriptionStatus` | Plan name and subscription status. | **Confirmed** that the keys exist. Their values were not read. |
| **Cursor** (usage %) | No documented local source. Options: (a) an undocumented dashboard endpoint called with the local `cursorAuth/accessToken`; (b) the Admin API for Team plans, with an admin key. | Usage % (a), or team-wide usage (b). | **Needs verification, and fragile.** The Cursor forum reports the dashboard endpoint returning 400 for an empty body. Use an opt-in toggle, read the token only in memory, and never log or store it. |
| **Antigravity** | None on disk. The CLI log (`~/.gemini/antigravity-cli/cli.log`) shows `doRefreshQuota` calls, so quota is fetched from a backend. The log does not record the numbers. Both state databases (`Antigravity`, `Antigravity IDE`) have no quota keys. The `modelCredits` key holds encoded flags, not numbers. | Nothing usable yet. Reproducing the fetch would mean using Antigravity's own OAuth login, which needs the user's explicit consent. | **Unknown.** Next step is a spike: capture the app's quota request while its usage view loads, and confirm the response shape. The OAuth files are never read or copied. |
| **API spend (optional)** | Anthropic and OpenAI usage/cost APIs, with admin-level keys | Pay-as-you-go spend, not subscription limits. | **Needs verification** of current endpoints and key types at implementation time. Labelled as "API spend" in the UI. |

**Web sources.** These were found by search. I have not opened the pages, so the claims above rest on search summaries.
- Claude Code status line `rate_limits` field: [skoula.cz guide](https://skoula.cz/blog/2026/6/how-to-display-context-and-5h-7d-limits-in-the-claude-code-status-bar/), [israynotarray.com setup guide](https://israynotarray.com/en/ai/2026/03/26/claude-code-status-line-setup-guide/), and [anthropics/claude-code#45133](https://github.com/anthropics/claude-code/issues/45133). That last issue appeared in search results. I have not confirmed it is the one that reports the field missing.
- Cursor: [usage limits help page](https://cursor.com/help/models-and-usage/usage-limits.md), and a [forum thread on usage info](https://forum.cursor.com/t/i-cant-get-my-usage-info/155469) that search linked to the 400 report. The thread was not confirmed by opening it.
- Cursor Admin API: only third-party guides found. Check it against Cursor's official API reference before building on it.

## 5. Constraints and decisions

- **No App Sandbox.** A sandboxed app cannot read `~/.codex`, `~/.claude`, or other apps' Application Support folders. Distribute as a Developer ID–signed, notarized app or a local build. It cannot ship on the Mac App Store in this form. (Alternative: user-granted security-scoped bookmarks for each folder. That is more setup, but keeps the sandbox.)
- **Secrets.** Every key and token the app stores goes in the Keychain. Cursor's token is read live, in memory only, and is never copied or logged.
- **Consent.** Anything that reads another app's credentials, or edits another app's settings, is off by default, with an explicit toggle and a preview of the change.
- **Freshness.** Local data is a snapshot from the last session. Every card shows an "as of" time. When `resets_at` has passed, the window shows as STALE or reset, not the old percentage.
- **Minimum macOS: 14 (Sonoma).** Recommended, since it allows `@Observable` and a current SwiftUI `MenuBarExtra`. Confirm this.
- **No telemetry.** The app calls only the provider endpoints the user has chosen.
- **Stored state.** Snapshots and settings go in `~/Library/Application Support/Phosphor/`. Read logs from their tail. Never load a whole multi-megabyte JSONL into memory.

## 6. Architecture

- **Stack:** Swift 6, SwiftUI. `MenuBarExtra` with `.window` style. `LSUIElement = YES` (no Dock icon). Xcode 27 is installed here.
- **Modules:**
  - `Providers/`: a `UsageProvider` implementation per provider.
  - `Sources/`: file watchers (FSEvents) and JSONL tail parsers.
  - `Secrets/`: Keychain wrapper.
  - `Store/`: `UsageStore` (`@Observable`), which owns snapshots, the poll timer and snapshot cache.
  - `UI/`: menu bar label, dashboard, sources screen, settings.
  - `Theme/`: palette, pixel glyphs, bundled fonts.
- **Core types (sketch):**

```swift
protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    func snapshot() async throws -> ProviderSnapshot
}

struct UsageWindow: Sendable {
    var label: String          // "5H", "WK", "MO"
    var usedPercent: Double?   // nil = unknown
    var resetsAt: Date?
}

struct ProviderSnapshot: Sendable {
    var windows: [UsageWindow]
    var plan: String?
    var tokens: TokenTotals?
    var asOf: Date
    var source: SourceKind     // .localFile, .statusLineHelper, .localToken, .apiKey
}
```

- **Display state** is computed, not stored: LIVE if `asOf` is recent and no reset has passed; STALE if a reset has passed or the snapshot is old; NO SOURCE if the provider has no configured source.

## 7. Setup flow

1. First launch shows the Sources screen. The app detects what it can see locally (for example, "found `~/.codex`, 30 rollouts") and proposes a source for each provider.
2. Pick a source per provider. Optional API-spend keys go to the Keychain.
3. Connecting the Claude Code status line helper shows the exact lines it would add to `~/.claude/settings.json`, and asks before writing.
4. Cursor's opt-in reads its local token only after an explicit confirmation.
5. Done: the menu bar shows the pinned providers.

## 8. Milestones

| Milestone | Scope | Exit check |
|---|---|---|
| **M0** (this turn) | Git repo, this plan, design mockup | Plan and mockup reviewed |
| **M1** | Xcode project, `MenuBarExtra` skeleton, Phosphor theme, pixel glyphs, mock providers | Menu bar item and dropdown render with fake data |
| **M2** | Codex local provider, STALE logic | Real Codex numbers appear, and the stale snapshot shows STALE |
| **M3** | Claude Code: token totals and the status line helper | Spike first: confirm `rate_limits` appears in the status line JSON on this Mac |
| **M4** | Sources screen, Keychain, notifications, thresholds, launch at login | Full setup works from a clean state |
| **M5** | Cursor (opt-in) and Antigravity spikes | Each one has a confirmed source or a documented "not possible" |
| **M6** | Themes, polish, signing, notarization, DMG | Installs and launches on a clean Mac |

## 9. Open decisions

1. **Name.** Phosphor, or one of the alternatives above?
2. **Minimum macOS.** 14 (Sonoma), or lower?
3. **Distribution.** Personal use only, or shared with others? This decides whether notarization is needed.
4. **Cursor's local token.** Is reading it, as an opt-in, acceptable? The alternative is a pasted key or admin access only, which covers Team plans only.
5. **API spend.** Which keys do you have? Anthropic admin, OpenAI admin, or none?
6. **Antigravity quota.** Its quota comes from a backend call made with the app's own OAuth login. Is a spike that captures that request acceptable, or should Antigravity wait until a local source turns up?
