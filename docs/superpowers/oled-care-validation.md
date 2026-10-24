# OLED care validation — 2026-10-24

Local policy verification: `./scripts/test-oled-core.sh` passes 13 XCTest tests
against the production Foundation source. The direct Swift compiler harness uses
macOS XCTest; it does not emulate tvOS or replace native integration validation.
Layering checks and Swift syntax parsing for the changed native files pass.

TDD evidence:
- Configuration/session suite first failed on missing OLED care types, then 8 tests passed.
- Safe movement/rotation geometry first failed on the missing geometry type, then 10 tests passed.
- Background partial-interval regression failed 1 of 11 before preserving elapsed viewing;
  all 11 passed after the fix.
- Ordinary minute-29 remote input incorrectly postponed the minute-30 break; the new
  regression failed 1 of 13 before the fix, then all 13 passed. Outage-dim remote
  grace remains covered separately, including expiry at exactly 300 seconds.

Native tests include full-black renderer pixel samples, idle inhibition/background,
unavailable/recovery output, consumed wake, device preferences across disconnect,
and remote brightness editing with persistence after relaunch. Native UI tests
were authored before the page, but the local RED attempt could not execute tests.

Local native validation is blocked externally: `./build-and-run.sh --test` cannot
connect to CoreSimulatorService; generic tvOS `xcodebuild ... CODE_SIGNING_ALLOWED=NO
build` encounters Swift macro plugin-server malformed responses under the host
sandbox. Neither native test execution nor native build success is claimed from
these attempts. Repository CI must validate the final native implementation.

Implementation rulings:
- AppModel owns the monotonic session across viewer recreation and polls.
- Background pauses partially elapsed viewing; leaving during an active periodic
  break cancels it, so return is visible and begins a fresh interval.
- Ordinary remote input does not move a break deadline. Rest input consumes the
  wake press and restarts the interval. Outage-dim input grants temporary grace
  without restarting the break interval.
- Configuration loads fields independently, preserving valid fields when another
  field is malformed or contains an unknown future enum case.
- The optional invitation is non-focusable explanatory text in the panel-browser
  heading, pointing to Settings → OLED care. Settings remains the single vertical
  gateway out of the card grid.

Physical OLED effectiveness is unmeasured; no burn-in prevention is claimed.

## Native focus regression follow-up

CI run 40123178497 successfully archived the app but reproduced a focus regression
in `PanelsPresentationTests.testTwoColumnsFitAndRemoteCanBrowseEveryRow` at line
88. Grid traversal and returning to Office succeeded. Its failure hierarchy and
screenshot show that repeated Up commands leave focus on the added OLED toolbar
button, whose center overlaps the right-column cards; Settings is farther right.
The existing regression test is retained unchanged. The optional invitation is
now non-focusable heading text that points to the dedicated Settings page,
restoring Settings as the header's only remote focus target. The OLED UI test
continues to enter through Settings and checks dismissal of the invitation text.
Native GREEN for this correction awaits the next CI run.
