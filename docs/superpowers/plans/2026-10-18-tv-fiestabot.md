# Apple TV FiestaBot Implementation Plan

> **For agentic workers:** Use executing-plans for inline work and dispatch independent domains to isolated agents. Steps use checkbox status.

**Goal:** Chat with FiestaBot and display results through the native Apple TV viewer.
**Architecture:** A FiestaClient extension streams structured SSE over its existing authenticated session. A main-actor model owns transcript and decisions. A native chat route preserves its session while switching to a panel viewer. Backend resolves true panel context.
**Tech Stack:** Foundation URLSession AsyncBytes, SwiftUI/XCTest, existing Python AI agent.
**Spec:** ../specs/2026-10-18-tv-controls-design.md

## Global Constraints
- No browser follow-me UI, new AI provider, credential copying, automatic stream retries, or silent schedule disabling.
- Keep app tests and PR checks enabled. Preserve current privacy disclosures accurately.

## Review Focus
- A dropped stream after a tool call must not replay an action.
- Approval and questions remain answerable after a request failure.
- Page/display IDs are distinct; target the selected panel's board.
- Disabled/unconfigured AI and partial tool failures must be visible.
- Chat history must not leak to a replacement connection.

### Task 1: Transport and board context
Files: new Core/FiestaChat.swift and Core/FiestaClient+Chat.swift, Tests/FiestaChatTests.swift; backend chat context/prompt tests in isolated web checkout.
- [x] Pin SSE framing, JSON payloads, structured replay and request targeting in tests.
- [x] Implement arbitrary JSON wire values, events, request and streaming API using existing session. Expose exact interfaces to root before UI integration.
- [x] Resolve board type/geometry server-side and include the target identity in prompt. Preserve truthful action outcomes.
- [x] Run focused tests; compile native core.

### Task 2: Native interaction and viewer integration
Files: new UI/FiestaBotModel.swift and UI/FiestaBotScreen.swift; AppModel, RootView, ViewerOverlay/Screen, privacy docs/tests.
- [x] Test state transitions for text/tool/done, approvals/questions, interrupted streams and no automatic retry.
- [x] Implement text composer, suggestions, transcript, decisions, Stop/Continue, target panel selection and explicit display-result actions.
- [x] Keep session bound to connection; discard it when connection changes or signs out.
- [x] Add native UI coverage for opening FiestaBot from a viewer; compile and run hosted CI.

## Validation status

Implementation and focused validation are complete. Hosted CI is the final gate; fixes remain on PR branches. Actual physical Apple TV deployment, dictation, and remote feel still require device validation.
