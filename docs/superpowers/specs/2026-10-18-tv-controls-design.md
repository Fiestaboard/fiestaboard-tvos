# TV controls and FiestaBot

The user wants to configure the displayed panel from Apple TV, fix matrix TV sizing in the web UI, and ask FiestaBot to create pages or perform actions without opening the web UI. The existing native viewer remains the display surface. Browser follow-me choreography is out of scope. Start with native text entry, suggested commands, and readable replies; use system dictation where the keyboard supports it.

## Shared panel controls

Expose shared panel name, TV diagonal/aspect, calibration, render style, animations, matrix sizing/pitch, backdrop, and nightly dim window. Preserve local preferences as fallbacks for old servers. Shared matrix sizing must be optional; editing another field must not silently override local fallback behavior. Save only changed fields and validate bounds before PATCH. Warn about incompatible pages after resizing. A failed save keeps the draft. Controls open for the panel currently viewed. Explain that shared changes affect every viewer. Backdrop is a web-viewer decoration; native full-screen background remains black.

True LED size uses screen dimensions, pitch and calibration consistently. Matrix geometry must contain the complete panel cell grid after resize, without clipping or reflow. Editing web matrix parameters updates its preview. Respect existing work in the web checkout by copying related changes to an isolated branch.

## FiestaBot

Use the existing authenticated server-side agent via POST /pages/ai/chat; no provider secrets or AI execution on Apple TV. Target the current panel's actual board ID and geometry. The backend must provide correct panel context rather than describing it as a flagship board. Retain structured transcript including tool calls/results for follow-up turns. Stream replies, display tool progress/results, preserve required approvals and questions, offer Continue at turn limits, and support stopping. Never automatically replay a stream once it has started; interrupted writes may have completed.

Expose FiestaBot from the viewer, keep conversation while visiting the viewer, and let the user select a target panel. Provide native panel opening and explicit Show page controls for successful page results. Use a one-off send with clear feedback unless a temporary override API exists; do not silently disable schedules. Open the existing panel viewer after confirmed display success. AI configuration errors should direct the user to the existing board setup, without implying AI is available when it is disabled. Update privacy copy to explain that requests may reach the board's configured AI provider.

## Validation

Meaningful tests cover minimal patches, invalid numeric/time input, matrix physical geometry and complete content, streaming event boundaries, transcript replay, approval/question continuation, interrupted streams, truthful action failures, and current-panel targeting. Local simulator services are unavailable, so compile locally and use hosted tvOS CI for runtime UI tests. Keep the existing CI/signing/focus PR separate and verify its screenshots.
