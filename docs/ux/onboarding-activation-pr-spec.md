# Onboarding and Activation UX PR Spec

## Context

This spec defines implementation-ready UX updates for repository-facing onboarding and activation content. Scope covers README and website copy only (no app UI code changes).

## UX Goals

- Decrease time-to-first-value for new users running local terminal agents.
- Make first-run setup deterministic with a validation loop users can execute in under 10 minutes.
- Reduce abandonment from setup blockers by documenting exact remediation actions.

## Target Users

- Solo builders running multiple local agents.
- Small engineering teams coordinating parallel terminal sessions.
- DevRel/product teams demonstrating local agent workflows.

## Required Content Changes

### 1) README activation path

Add a dedicated "First 10 Minutes" checklist after install and before broad CLI reference.

Checklist content should include:

1. Run installer and launch `Overwatchr.app`.
2. Grant Accessibility permission.
3. Install hooks (`overwatchr hooks install all --scope user`) and shell sync.
4. Trigger deterministic test alerts (one success and one error sample).
5. Validate success criteria from menu bar queue and jump shortcut.

### 2) README failure remediation

Add a "If activation fails" section with common blockers and fix steps:

- Accessibility permission missing.
- Hooks not installed or stale config.
- Shell title sync not installed for title-based matching cases.
- Unsupported terminal app.

### 3) Website onboarding band

Update install/get-started content to communicate a complete activation loop, not only installation.

Requirements:

- Include a first-run 4-step sequence: install, grant permission, install hooks, run test alert.
- Add explicit expected success state: queue badge visible and shortcut jump returns to target tab.
- Include concise blocker fallback note that points users to README troubleshooting.

## Copy Constraints

- Keep language concrete and operator-oriented.
- Avoid generic marketing claims in setup sections.
- Prefer command-level specificity over abstract guidance.

## Acceptance Criteria

- README includes a "First 10 Minutes" section with exact commands and expected outcomes.
- README includes an "If activation fails" remediation section with at least 4 blocker/fix entries.
- Website install/onboarding section includes test-alert validation and explicit success criteria.
- Website onboarding section includes troubleshooting pointer to README.
- Changes are PR-reviewable without additional UX clarification.

## Handoff

Engineering and marketing owners should implement directly from this spec and retain section headings for traceability in review.
