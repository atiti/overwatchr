# Contributing

Thanks for helping improve Overwatchr.

## Development

```bash
swift build
swift test
swift run overwatchr-app
```

If you touch packaging or installer behavior, also run:

```bash
scripts/build_app_bundle.sh
```

## Pull Requests

Please keep PRs focused and include:

- what changed
- why it changed
- how you verified it
- screenshots or short screen recordings for UI changes

If you change hook integrations, mention which tool and config path you tested.

## Quality Bar

- keep it native macOS
- avoid external runtime dependencies
- prefer small, inspectable changes over large rewrites
- add or update tests when behavior changes

## Release Notes

If your PR changes installation, hook behavior, or visible menu bar UX, include a short release note suggestion in the PR description.
