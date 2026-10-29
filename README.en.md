# TypingStats

[简体中文](README.md) | English

A local typing tracker that lives in the macOS menu bar. It counts how much you type each day, and bundles a few everyday tools: clipboard history, a timestamp converter, an input source lock, a launchd job manager and a network speed test.

Keystroke tracking **counts only and never records content**. Data stays on your Mac and in your own iCloud Drive.

## Features

### Typing stats
- **System-wide counting**: counts letter and digit key presses in every app, including self-drawn ones like terminals and WeChat. Punctuation, space, Return, arrow keys, Delete and key auto-repeat are ignored.
- **Character estimate**: characters = keystrokes ÷ keystrokes per character (default 2.0, adjustable from 1.0 to 6.0; around 2–3 for Chinese pinyin, 1 for plain English).
- **Menu bar**: shows today's count (e.g. `1.2k`). The panel shows this Mac vs. other devices, CPU temperature and memory usage.
- **Today dashboard**: today's total, change vs. yesterday, and hourly / 7-day / 30-day charts stacked by device.
- **History**: 7 / 30 / 90-day bar charts with totals and daily averages.
- **Per-app ranking**: today's typing by app. Apps can be excluded from counting.
- **iCloud sync**: merges stats from all your Macs through iCloud Drive. Totals cover all devices by default.
- **Export**: full history as CSV or JSON.

### Tools
| Tool | Where | What it does |
|---|---|---|
| Clipboard history | `⌃⌥⌘V` / main window "剪贴板" | Keeps the last 50 text and image items. In the picker, `↑↓` selects, `Return` pastes, `1`–`8` pastes directly. |
| Timestamp converter | `⌃⌥⌘T` | Converts between Unix timestamps (seconds / milliseconds) and dates. Prefills from the clipboard and pastes the result back into the previous app. |
| Input source lock | Menu bar panel / Settings | Switches back to your chosen input source when something changes it, at most once every 2 seconds. |
| launchd jobs | Main window "定时任务" | Lists your launchd jobs with schedules, next run time and logs. Enable, disable or run a job once. |
| Network speed test | Main window "更多 → 网络测速" | Runs macOS's built-in `networkQuality` for throughput, latency and RPM. |

Both global shortcuts can be re-recorded in Settings → 通用. Main window pages use `⌘1`–`⌘6`.

> The interface is currently in Simplified Chinese only.

## Requirements

- macOS 13 Ventura or later
- Accessibility permission (for keystroke counting, global shortcuts and auto-paste)

## Installation

1. Open `TypingStats-<version>.dmg` and drag TypingStats into Applications.
2. Launch it, click the warning icon in the menu bar and choose "授予权限" (Grant permission).
3. Turn on TypingStats in System Settings → Privacy & Security → Accessibility. Counting starts automatically, no restart needed.

> Current builds are signed with a development certificate and are not notarized. On another Mac you may need to right-click → Open, or click "Open Anyway" in Privacy & Security.

## Building from source

Requires Xcode 15 or later (Swift 5.9).

```bash
make build       # swift build -c release
make app         # build and sign .build/TypingStats.app
make run         # build and launch (stops any running instance first)
make test        # run tests
make dmg         # build .build/TypingStats-<version>-<timestamp>.dmg
make reset-perm  # reset the Accessibility grant
```

Builds are ad-hoc signed by default, so you may have to re-grant Accessibility after each rebuild. To sign with a stable certificate and keep the grant across rebuilds, create `signing.local.mk` in the repo root (it's in `.gitignore`):

```make
SIGN_ID := Apple Development: Your Name (TEAMID)
```

Or pass it once: `make app SIGN_ID="…"`. List available certificates with `security find-identity -v -p codesigning`.

## Privacy

- Keystroke tracking only checks whether a key is a letter or digit and increments a counter. Which key you pressed and what you typed are never stored.
- The app talks to no servers. The only network traffic comes from iCloud Drive syncing the stats snapshots, and from speed tests you start yourself.
- Clipboard history stores copied text and images as-is, on this Mac only. It is not synced and can be cleared at any time.

## Data locations

| Data | Path |
|---|---|
| Stats database | `~/Library/Application Support/TypingStats/typingstats.sqlite` |
| Clipboard history | `~/Library/Application Support/TypingStats/clipboard-history.json`, `ClipboardImages/` |
| Sync snapshots | `~/Library/Mobile Documents/com~apple~CloudDocs/TypingStats/<device-id>.json` |

## Known limitations

- Character counts are estimates: mixed Chinese/English input, word predictions, and Wubi or double-pinyin layouts skew the result.
- Pasted text, dictation and handwriting input are not counted.
- iCloud sync lags by a few seconds to a few minutes.

See [需求说明书.md](需求说明书.md) (Chinese) for the full requirements and design notes.
