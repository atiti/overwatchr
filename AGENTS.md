# Repository Guidelines

## Project Structure & Module Organization

This repo is a single Swift Package for a native macOS utility. Keep shared logic in `Core/`, the menu bar app in `App/`, and the CLI entrypoint in `CLI/`. Unit tests live in `Tests/OverwatchrCoreTests/`. Root files such as [`Package.swift`](/Users/attilasukosd/build/overwatchr/Package.swift), [`install.sh`](/Users/attilasukosd/build/overwatchr/install.sh), and [`README.md`](/Users/attilasukosd/build/overwatchr/README.md) are part of the product surface, not afterthoughts.

## Build, Test, and Development Commands

- `swift build`: build the library, CLI, and menu bar app binaries.
- `swift test`: run the core unit tests.
- `swift run overwatchr`: run the CLI locally.
- `swift run overwatchr-app`: launch the status bar app from the package.
- `./install.sh`: build release binaries, install the CLI, and create `Overwatchr.app`.
- `scripts/build_app_bundle.sh`: build `dist/Overwatchr.app` plus release zip artifacts.
- `scripts/smoke.sh`: run the release build, launch the app, write a temporary alert, and verify the hotkey focus path.

## Coding Style & Naming Conventions

Use standard Swift formatting: 4-space indentation, one type per file when practical, `UpperCamelCase` for types, `lowerCamelCase` for methods and properties, and explicit names over abbreviations. Keep AppKit and Carbon code isolated from the pure Foundation event/store logic in `Core/`. Prefer small value types, readable control flow, and pragmatic code a sleepy developer can still debug at 2 a.m.

## Testing Guidelines

Add unit tests for every meaningful change in `Core/`, especially queue semantics, JSONL persistence, and status transitions. Name test files after the subject under test, such as `EventStoreTests.swift`, and use descriptive test names like `testDoneRemovesAlert`. Run `swift test` before opening a PR and do a quick manual menu-bar smoke test when UI or focus behavior changes.

## Commit & Pull Request Guidelines

Git history is minimal, so follow the existing concise imperative style from `Initial commit`: short subject line, present tense, focused scope. PRs should include:

- a brief summary of the user-visible change
- test evidence (`swift test`, manual menu bar verification)
- screenshots or a short recording for menu bar or focus-behavior changes
- linked issues or follow-up items when relevant

## macOS Notes

Window focusing relies on native macOS APIs and may require Accessibility permission. Keep the app menu-bar-only, dependency-free, and compatible with Ghostty, iTerm, and Terminal.app. If you add new terminal support, keep the API surface small and the failure modes obvious.
