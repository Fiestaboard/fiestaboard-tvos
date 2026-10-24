# Weekly App Store Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Prepare the FiestaBoard listing and automate weekly public tvOS releases after Apple approval.

**Architecture:** Keep GitHub Actions CI and use a tested Python release planner with Fastlane delivery. Install distribution signing material only in an ephemeral runner keychain. Generate media independently with opt-in UI automation.

**Tech Stack:** GitHub Actions, Python standard library, OpenSSL, XcodeGen, Xcode 26+, Fastlane 2.241.1.

**Spec:** docs/superpowers/specs/2026-10-24-app-store-release-design.md

## Global Constraints

- Release only an exact `main` commit with successful `build-and-test` and `Release archive` jobs.
- Home UI remains informational; no existing branch protection is weakened.
- No secrets in source control or logs; both bundles retain `group.com.fiestaboard.tv`.
- Weekly runs skip unchanged app sources and active review; rejected versions need attention.
- Weekly public submission is enabled only after first-release readiness.

## Review Focus

- An optional CI failure must not hide success of the required jobs.
- Failed uploads/submissions must not mark a commit released.
- A later weekly run must not submit the same app source again.
- A rejected or already-uploaded draft must not be overwritten automatically.
- An upload-only first-release run must not submit for public review.

### Task 1: Release planning and delivery configuration

**Files:** scripts/app-store-release.py, scripts/test-app-store-release.py, fastlane/Fastfile, .github/workflows/app-store-release.yml, .github/workflows/ci.yml.

**Interfaces:** Planner reads Apple version state, source change state and exact-SHA GitHub job results; emits `publish`, `version`, and `reason`. Workflow consumes those outputs and supplies Fastlane with the exported IPA/version/build number.

- [ ] Write behavioral tests for required CI checks, unchanged sources, active/rejected states, first 1.0 draft and patch increments; run and observe failure.
- [ ] Implement planner and run tests to pass. Expected: zero failures.
- [ ] Add isolated signing/export and Fastlane upload/submission workflow, gated schedule and manual upload-only mode; include planner tests in CI.
- [ ] Run Python tests, Ruby syntax, bash syntax and actionlint. Expected: all pass.
- [ ] Commit configuration and verify PR CI. Expected: required CI jobs pass.

### Task 2: Store materials and launch readiness

**Files:** fastlane/metadata/en-US/*, docs/PRIVACY.md, docs/SUPPORT.md, docs/PUBLISHING.md, media workflow and opt-in UI capture test.

**Interfaces:** Version metadata lives in repo; media workflow returns native screenshots and walkthrough video. Apple review details retain contact data privately in App Store Connect.

- [ ] Save factual metadata/privacy/support content, correct stale publishing instructions, and prepare current media.
- [ ] Update and read back supported App Store fields; verify uploaded screenshot/video processing states.
- [ ] Configure encrypted signing/API secrets and verify signing profile entitlements.
- [ ] Validate the workflow with a manual upload-only run once CI passes. Expected: processed public-eligible build, no review submission.
- [ ] Report any launch declarations or physical acceptance evidence still needed; enable weekly submission only when those are resolved.
