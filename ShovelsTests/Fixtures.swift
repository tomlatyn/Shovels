//
//  Fixtures.swift
//  ShovelsTests
//
//  Created by Tomas Latyn on 13.10.26.
//

/// Real CLI output captured on 13 Oct 2026, with terminal codes removed and the account email replaced.
/// When a vendor changes its screen, capture the new one and add it here.
enum Fixtures {
    /// `claude -p /usage`, Claude Code 2.1.
    static let claude = #"""
You are currently using your subscription to power your Claude Code usage

Current session: 8% used · resets Oct 13 at 4:30pm (Europe/Prague)
Current week (all models): 7% used · resets Oct 14 at 1am (Europe/Prague)

What's contributing to your limits usage?
"""#

    /// The reply to `account/rateLimits/read` from `codex app-server`, free plan.
    static let codex = #"""
{"id": 2, "result": {"rateLimits": {"limitId": "codex", "limitName": null, "primary": {"usedPercent": 0, "windowDurationMins": 43200, "resetsAt": 1794478346}, "secondary": null, "credits": {"hasCredits": false, "unlimited": false, "balance": null}, "individualLimit": null, "spendControlReached": false, "planType": "free", "rateLimitReachedType": null}}}
"""#

    /// agy 1.3.4 after typing /usage: startup, the command menu, then the Models & Quota panel with two groups.
    static let antigravity = #"""
>q>4m>4;2m>1u
▄▀▀▄
▀▀▀▀▀▀
▀▀▀▀▀▀▀▀
  ▄▀▀    ▀▀▄
 ▄▀▀      ▀▀▄
 Welcome to the Antigravity CLI. You are currently not signed in.
 ⣷  Signing in...
 ⣯
 ⣟
 ⡿
 ⢿
 ⣻
 ⣽
 ⣾
 ⣷
 ⣯
 ⣟
 ⡿  ▄▀▀▄        Antigravity CLI 1.3.4
 ▀▀▀▀▀▀       user@example.com
 ▀▀▀▀▀▀▀▀      Gemini 3.8 Flash (High)
   ▄▀▀    ▀▀▄     ~
  ▄▀▀      ▀▀▄
⚠ Warning
  ⎿  "Gemini 3.6 Flash (High)" is no longer available. Using "Gemini 3.8 Flash (High)".
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
>
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
? for shortcutsGemini 3.8 Flash · high · AI: Out of credits
 ┃ Verbosity now defaults to medium
 ┃ Verbosity is now medium by default, so tool calls and thoughts roll up into summaries. You can change your
 ┃ preferred verbosity anytime in /config > Verbosity.
 ┃ esc to dismiss
 (Google AI Pro)/
> /add-dir             Add a directory to the workspace
  /agentsList available custom agents
  /artifact            View and review artifacts
  /btwAsk a side question without interrupting the current task
  /changelog           Show release notes and changes
   ↓ 41 more
  ↑/↓ Navigate · enter Select · tab Complete
esc to cancelGemini 3.8 Flash · high · AI: Out of credits
u
rewind (undo)       Rewind conversation to a previous message
usageView model quota usage
exitExit the CLI
logoutLog out
pluginManage, discover, install, uninstall, enable, and disable plugins
6
s
usage               View model quota usage
statusline          Toggle the statusline
agy-customizations  Comprehensive guide and reference for the Antigravity Customization System. Use to explain ho...
a
g
	 /usage
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
>
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
└ Models & Quota
  Account: user@example.com
GEMINI MODELS
  Models within this group: Gemini Flash, Gemini Pro
  Weekly Limit Remaining
    [██████████████████████████░░░░░░░░░░░░░░░░░░░░░░░░] 51.30%
Refreshes in 50h 19m
  Five Hour Limit Remaining
[██████████████████████████████████████████████████] 100.00%
Quota available
CLAUDE AND GPT MODELS
  Models within this group: Claude Opus, Claude Sonnet, GPT-OSS
  Weekly Limit Remaining
[█████████████████████████████████████████████████░] 98.55%
Refreshes in 157h 55m
  Five Hour Limit Remaining
[██████████████████████████████████████████████████] 100.00%
Quota available
  │Within each group, models share a weekly limit and a 5-hour limit. Quota is
  │consumed proportionally to the cost of the tokens. Thus, limits will last
  │longer with shorter tasks or using more cost-effective models. The 5-hour
  │limit smooths out aggregate demand to fairly distribute global capacity
  │across all users, while your weekly limit is tied directly to your individual
  │tier.
  ↑/↓ Scroll · pgup/pgdown Page · ctrl+end Bottom · ctrl+home Top · esc Close
? for shortcutsGemini 3.8 Flash · high · AI: Out of credits G
press ctrl+c again to exit
"""#

    /// Cursor's agent after typing /usage, from the command menu to the usage panel.
    static let cursor = #"""
   → /usage                    Show plan and on-demand usage
     /context                  Show context usage breakdown
     /create-subagent          Create custom subagents for specialized AI tasks. Use when you want to create a new…
  Loading usage data...
  Auto
  ~/Library/Application Support/Shovels/cursor-workspace
  Loading usage data...
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
 Usage • Pro                                                                                            Resets Oct 18
 Monthly plan and on-demand usage
 Category        Current             Usage
 Included        88% used            ██████████████████████████████████████████████████████████████████████░░░░░░░░░░
   Auto          87% used            ██████████████████████████████████████████████████████████████████████░░░░░░░░░░
   API           100% used           ████████████████████████████████████████████████████████████████████████████████
 On-Demand       Disabled            ————————————————————————————————————————————————————————————————————————————————
 On-demand usage is off
 View in dashboard: cursor.com/dashboard?tab=usage
 Esc to close
"""#
}
