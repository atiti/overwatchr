# overwatchr

overwatchr is a native macOS menu bar sidekick for terminal-based AI agents. Your agents keep doing their thing in Ghostty, iTerm, or Terminal; overwatchr sits in the menu bar, spots anything that needs a human, and jumps you back to the right window fast.

## Why it exists

When a few agent sessions turn into ten, context switches get messy. overwatchr gives you one small control tower that:

- watches `~/.overwatchr/events.jsonl`
- shows active alerts in the menu bar
- lets you hop to the next alert with `Cmd+Shift+A`
- brings Ghostty, iTerm, or Terminal to the front

## Repository layout

- `App/`: SwiftUI status-bar app
- `CLI/`: tiny `overwatchr` command writer
- `Core/`: shared event, queue, watcher, and focus logic
- `scripts/`: app bundling, icon generation, and smoke-test helpers
- `Tests/OverwatchrCoreTests/`: unit tests for the boring-but-important bits
- `install.sh`: release build and local install helper

## Build and run

```bash
swift build
swift test
swift run overwatchr-app
scripts/smoke.sh
```

No config is required to get started, but exact window focusing works best when Accessibility access is granted in macOS System Settings.

## Install

Local install:

```bash
./install.sh
```

One-line install after publishing:

```bash
curl -sSL https://raw.githubusercontent.com/<your-org>/overwatchr/main/install.sh | bash
```

The script installs:

- `overwatchr` into `/usr/local/bin` by default
- `Overwatchr.app` into `/Applications` or `~/Applications`

If you want a distributable app bundle and archives without installing them, run:

```bash
scripts/build_app_bundle.sh
```

That produces:

- `dist/Overwatchr.app`
- `dist/overwatchr-<version>-macos-app.zip`
- `dist/overwatchr-<version>-macos-cli.zip`

## CLI usage

```bash
export AGENT_ID=copy

overwatchr alert \
  --agent "$AGENT_ID" \
  --project landing \
  --terminal ghostty \
  --title "landing:copy"

overwatchr error \
  --agent "$AGENT_ID" \
  --project landing \
  --terminal ghostty \
  --title "landing:copy"

overwatchr done --agent "$AGENT_ID" --project landing
```

Each command appends a JSON object to `~/.overwatchr/events.jsonl`. `done` clears the agent from the in-memory alert queue, while `alert` and `error` keep it visible until a later `done` event arrives.

That makes it easy to drop into agent wrappers or shell hooks. The contract is intentionally tiny: write events, let the menu bar app do the watching.

## Notes

- Supported terminals in the MVP: Ghostty, iTerm, Terminal.app
- The menu bar item is intentionally tiny: it stays quiet when idle and shows an alert count when humans are needed
- No Electron, Node UI, Hammerspoon, tmux, or external runtime dependencies
- The app is menu bar only and hides its Dock icon

## Precompiled binaries

Once GitHub Releases are enabled, tagged builds (`v0.1.0`, `v0.2.0`, and so on) will publish:

- a zipped `Overwatchr.app`
- a zipped standalone `overwatchr` CLI binary

The repository includes:

- `.github/workflows/ci.yml` for build/test validation
- `.github/workflows/release.yml` for tagged release packaging
