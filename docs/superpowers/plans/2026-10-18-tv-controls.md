# TV Controls Implementation Plan

> **For agentic workers:** Use executing-plans for inline work and dispatch independent domains to isolated agents. Steps use checkbox status.

**Goal:** Edit all shared panel display settings on Apple TV and make matrix sizing work consistently in both viewers.
**Architecture:** A validated panel-settings draft builds a minimal PATCH. Native settings own their save lifecycle; shared matrix presentation feeds existing renderers. Web changes build on the existing uncommitted matrix work in an isolated checkout.
**Tech Stack:** Swift/SwiftUI, XCTest, React/TypeScript/Vitest, Python/Pydantic/pytest.
**Spec:** ../../specs/2026-10-18-tv-controls-design.md

## Global Constraints
- Preserve original workspaces and use PR branches; no main pushes or merges.
- Keep local settings fallback for older servers and nullable shared matrix sizing.
- Native full-screen background stays black; label backdrop as a web viewer setting.

## Review Focus
- A rename must not change matrix sizing or overwrite other server settings.
- NaN, empty numeric input, invalid times, unsupported server fields cannot become successful saves.
- Matrix resize must display every cell without cropping.
- Errors retain a retryable draft and do not navigate away.
- Current panel selection persists when returning from settings.

### Task 1: Native panel controls
Files: new Core/PanelSettingsDraft.swift, UI/PanelDisplaySettingsScreen.swift; existing FiestaClient, SettingsModel/Screen, MatrixDisplay, Models; focused tests.
- [ ] Add regression tests for changed-only patches, nullable sizing, validation, calibration and dimensions.
- [ ] Implement draft, PATCH overload, shared editor, matrix calibration/aspect handling. Keep existing quick controls.
- [ ] Leave FiestaClient.session and url(for:) module-internal for the separate chat extension.
- [ ] Compile app/tests; run available portable tests. Root runs hosted runtime checks.

### Task 2: Web matrix sizing
Files: existing related matrix diff plus panel model geometry and targeted tests.
- [ ] Copy related preexisting changes to an isolated worktree; do not edit original.
- [ ] Pin calibration, live matrix editor preview, preservation of unset sizing, and resized complete matrix geometry with tests.
- [ ] Fix each behavior and run targeted web/Python suites, typecheck and diff checks.
- [ ] Commit only relevant matrix feature changes and open a PR.
