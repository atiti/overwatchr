# overwatchr

[![CI](https://github.com/atiti/overwatchr/actions/workflows/ci.yml/badge.svg)](https://github.com/atiti/overwatchr/actions/workflows/ci.yml)
[![Release](https://github.com/atiti/overwatchr/actions/workflows/release.yml/badge.svg)](https://github.com/atiti/overwatchr/actions/workflows/release.yml)
[![License](https://img.shields.io/github/license/atiti/overwatchr)](./LICENSE)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.10%2B-orange)](https://www.swift.org/)

overwatchr is a native macOS menu bar utility for terminal-based AI agents. It watches for turns that need a human, keeps a queue in the menu bar, and jumps you back to the right terminal tab before your attention gets shredded.

It is built with Swift, SwiftUI, and native macOS APIs only. No Electron. No tmux dependency. No Hammerspoon.

## Why it exists

When Codex, Claude Code, OpenCode, or other terminal agents are running in parallel, the hard part is not starting them. It is noticing the exact moment one of them needs you, then getting back to the correct tab fast.

overwatchr gives you:

- a menu bar queue of live agent pings
- a global jump shortcut: `Ctrl+Option+Cmd+O`
- native terminal focusing for Ghostty, iTerm, and Terminal.app
- local `seen` behavior so opened alerts drop out until the next new event
- hook installers for Codex CLI, Claude Code, and OpenCode

## Install

One-line install:

```bash
curl -fsSL https://raw.githubusercontent.com/atiti/overwatchr/main/install.sh | bash
```

One-line install plus user-wide hook setup:

```bash
curl -fsSL https://raw.githubusercontent.com/atiti/overwatchr/main/install.sh | INSTALL_HOOKS=1 bash
```

By default, the installer:

- puts the CLI in `/usr/local/bin` if writable, otherwise `~/.local/bin`
- installs `Overwatchr.app` into `/Applications` if writable, otherwise `~/Applications`
- leaves hook config untouched unless you opt into `INSTALL_HOOKS=1`

From a local checkout:

```bash
./install.sh
```

If you only want the CLI:

```bash
INSTALL_APP=0 ./install.sh
```

If you want release artifacts without installing:

```bash
scripts/build_app_bundle.sh
```

## Quick Start

1. Install the app and launch `Overwatchr.app`.
2. Grant Accessibility access so terminal focusing works reliably.
3. Install hooks for the tools you use:

```bash
overwatchr hooks install all --scope user
```

That sets up:

- Codex CLI via `~/.codex/config.toml` and `~/.codex/hooks.json`
- Claude Code via `~/.claude/settings.json`
- OpenCode via `~/.config/opencode/plugins/overwatchr.js`

Project-local setup also works:

```bash
overwatchr hooks install all --scope project
```

## Manual CLI Usage

You can also write events directly:

```bash
overwatchr alert --agent copy --project landing --terminal ghostty --title "landing:copy"
overwatchr error --agent api --project backend --terminal iTerm2 --title "backend:api"
overwatchr done --agent copy --project landing
```

Events are appended to `~/.overwatchr/events.jsonl`.

Queue behavior:

- `alert` and `error` create or refresh an active alert for that agent
- opening an alert marks it `seen` locally, so it disappears until a newer event arrives
- `done` clears it from the active stream
- optional alert chime lives in the menu bar settings pane

## Hook Bridge

overwatchr includes a native bridge for hook-enabled tools:

```bash
overwatchr hook-run codex
overwatchr hook-run claude
overwatchr hook-run opencode
```

You usually do not call these by hand. The generated hook configs call them for you.

## Supported Terminals

- Ghostty
- iTerm
- Terminal.app

Ghostty uses both Accessibility window matching and a native `Window` menu fallback so tab switching is reliable even when AX window titles are not.

## Development

```bash
swift build
swift test
swift run overwatchr-app
scripts/build_app_bundle.sh
```

The repository layout is:

- `App/`: menu bar app
- `CLI/`: `overwatchr` executable
- `Core/`: shared queue, store, focus, hook, and installer logic
- `scripts/`: build and smoke helpers
- `Tests/OverwatchrCoreTests/`: unit tests

## Release Flow

- CI builds and tests on macOS via [`.github/workflows/ci.yml`](./.github/workflows/ci.yml)
- Tagged releases package the CLI and app via [`.github/workflows/release.yml`](./.github/workflows/release.yml)
- release tags should use `v*`, for example `v0.1.0`

## Roadmap

- more hook targets
- better terminal title inference
- signed and notarized app bundles
- optional richer notifications beyond the menu bar

## Contributing

Bug reports, hook integrations, terminal support fixes, and installer hardening are all welcome. See [`CONTRIBUTING.md`](./CONTRIBUTING.md).
