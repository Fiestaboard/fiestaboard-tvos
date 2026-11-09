# Hardware checklist (A12)

These are the release checks that need a real Apple TV. The owner runs them before TestFlight and before
every App Store submission. The Android twin is fiestaboard-androidtv's `docs/HARDWARE-CHECKLIST.md` (G11).

- **Which Apple TV:** judge performance on the **oldest supported model**, an Apple TV HD (A8, the oldest
  that runs the tvOS 18 floor). Run everything else on an **Apple TV 4K (3rd generation)** on the newest
  tvOS. Where a check says "both", repeat it on the HD.
- **What CI already covers:** the automated half is in CI. That means unit and snapshot tests, Apple's
  accessibility audit (`AccessibilityAuditUITests`), XCUITest focus and glass shots, the vocabulary guard,
  the licence and release-readiness tests, and the Release probe check. See
  [PUBLISHING.md](PUBLISHING.md#release-readiness-checks-a12).
- **Recording results:** add a row to the table at the end with the date, the device, the tvOS version,
  the build, pass or fail, and the evidence.

## Setup

- **Build under test:** the TestFlight build from the **Release** configuration, because it is what ships.
  - Debug builds carry the parity probes and run slower, so they are only for the timing items below that
    say "Debug build".
  - **Pass:** it installs from TestFlight, launches, signs in, lists panels, and shows a split-flap panel,
    an LED panel and a note array.
- **The hub:** a FiestaBoard hub on the same network, with:
  - a 6 × 22 flagship panel;
  - a 29 × 12 split-flap panel;
  - a 64 × 64 LED panel with a pixel canvas;
  - a 96 × 24 panel;
  - a note-array panel, both 2 × 2 Notes and one that isn't a whole number of Notes;
  - a panel with a schedule, an override and a silence (for the status chip).
- **Sign-in:** the TV is signed in with the phone (device credential), unless a check says otherwise.

## 1. VoiceOver walk-through

- **How:**
  1. Turn on Settings › Accessibility › VoiceOver.
  2. Walk each screen with the Siri Remote only.
  3. Repeat with Bold Text on.
- **Pass:** on every screen,
  - every focus stop is spoken with a name and a role, and none is just "button";
  - focus order follows reading order, and nothing focusable is invisible;
  - Menu (Back) leaves the screen;
  - with Bold Text on, no label is cut off.

| Screen | What to hear or check |
|---|---|
| Connect | The hub card names the hub and its address. "Enter hub address" is reachable. |
| Sign in with your phone | The QR is announced with its address, and the code is read as separate characters. "Use username and password" and "New code" are reachable. "Approved by …" is read once. |
| Your panels | Each card reads its name and what it shows. Settings is reachable. |
| Viewer | The board's message is read when it changes, politely. A status change (override, silence) is announced once. The controls appear on a press. "Hub unreachable · showing the last update" is announced. |
| Settings | The four categories, then every row reads its label and value. Home screen shortcut, Screen protection, Privacy and Licenses scroll with the remote and read in full. |
| OLED care | Every row reads its value; choice lists read the selected option. |

- **Evidence:** a screen recording with VoiceOver speech, or notes per screen.

## 2. Liquid Glass contrast, in a bright room and a dark one

- **How:**
  1. On tvOS 26 or later, open the viewer's controls (and let the status chip show) over each of these:
     - a white LED panel;
     - a busy pixel canvas;
     - a black split-flap board.
  2. Do it in a bright room (daylight or full lights) and again in a dark room, from 3 m.
  3. Repeat with Settings › Accessibility › Reduce Transparency on, which makes the controls opaque. On an
     Apple TV HD, which runs tvOS 18 and has no glass, check the regular material instead.
- **Pass:**
  - the panel name, the subtitle (muted text) and the chip text are readable at 3 m in both rooms;
  - the chip's dot and icons are distinguishable;
  - nothing shimmers or flickers.
- **Known (A12 finding G-1):**
  - The subtitle on glass over a pure-white board measured 4.33:1 in the simulator, against the 4.5:1 that
    the regular material meets.
  - Photograph this case from 3 m in the bright room and attach it to the designer's glass-tint decision.

## 3. Top Shelf text (DD26)

- **How:**
  1. Move FiestaBoard into the top row of the Home screen.
  2. Open the app once, so it publishes its previews.
  3. Go Home and focus the FiestaBoard icon.
  4. Wait for the carousel and move through its items.
  5. Repeat with a panel that has an override.
- **Pass:**
  - every item shows the panel's preview, with no text drawn into the image;
  - the system shows the panel's name (title) and the status line (`contextTitle`), for example "Override
    until 9:00 PM";
  - Play opens that panel and More Info opens Your panels.
- **Record:** whether the system shows the title and status text on this tvOS version. The tvOS 26 and 27
  simulators show none, and DD26 leaves this to hardware. A photo is the evidence.

## 4. LED redraw time on the oldest supported Apple TV

- **How:**
  1. On the Apple TV HD, install a **Debug build** with the launch argument `-fiestaboard.renderProfile YES`
     (Xcode › Scheme › Arguments).
  2. Open the 64 × 64 LED panel and let it change content 20 times; then do the same with the 96 × 24 panel.
  3. Download the app container (Xcode › Devices › the app › Download Container). Read
     `Library/Caches/matrix-preparation.json`, which holds up to 100 samples of `milliseconds` per redraw.
- **Pass:**
  - the **64 × 64 median ≤ 50 ms** and no sample over 100 ms (the same bar as Android's N25-3);
  - the 96 × 24 median is under 50 ms.
- **If it is above 50 ms:** draw the dots from pre-rendered per-colour sprites and re-measure.
- **Note:** a redraw happens only when the content or the geometry changes; playback reuses the prepared
  layers.

## 5. Frame rate of the split-flap board

- **How:**
  1. With a **Debug build** and `-fiestaboard.renderProfile YES`, open the 29 × 12 split-flap panel with
     Animations on, and send a full-board change from the hub ten times.
  2. Read `Library/Caches/flap-pacing.json`, which records the per-frame `cost` and timestamps.
  3. Also record the screen with an HDMI capture card and run
     `scripts/check-recording-pacing.py MOVIE --motion START:END` over the flip.
  4. Do it on the 4K and the HD.
- **Pass:**
  - **Apple TV 4K:** 60 fps flaps (the plan's A12 row): in the recording, no gap over 17 ms during the flip;
    the per-frame `cost` median is ≤ 8 ms.
  - **Apple TV HD:** no gap over 33 ms, and the flip finishes within its nominal time + 10 %.

## 6. Cold start

- **How:**
  1. Force-quit the app from the app switcher (double-press TV/Control Center, swipe up).
  2. Launch it from the Home screen and time it with a slow-motion phone video, from the click to the first
     board frame.
  3. Do it five times and take the median.
  4. Do it once with an open-at-launch panel set (which opens the viewer) and once without (which opens
     Your panels).
- **Pass:**
  - **Apple TV 4K:** median **≤ 2.0 s** to the first content;
  - **Apple TV HD:** median **≤ 3.0 s**;
  - never more than 5 s;
  - the taco loader never shows for more than 2 s on a reachable hub.

## 7. A 24-hour memory soak

- **How:**
  1. Open a busy panel, either a 64 × 64 LED panel with changing pixel art or a split-flap panel on a
     1-minute schedule. Set OLED care to Movement Gentle, and leave scheduled rest off so it keeps drawing.
  2. Attach Instruments › Allocations (or Xcode's memory gauge) to the TestFlight-equivalent Release build.
     Note the app's memory at hour 1 and at hour 24.
  3. Pull the hub's power for 10 minutes once during the soak, then restore it.
- **Pass:**
  - **Memory:** memory at 24 h is within **+15 %** of hour 1, with no steady climb.
  - **Stability:** no crash (Xcode › Devices › View Device Logs), and the board is still updating at the end.
  - **The outage:** "Hub unreachable · showing the last update" shows during it and clears within 15 s of
    the hub coming back.

## 8. OLED care on a real panel

- **How:** on an OLED TV, set each OLED care option in turn (Settings › This Apple TV › OLED care) and watch
  the viewer.
- **Pass:**
  - **Brightness:** it dims the board.
  - **Movement:** Gentle moves the board a few points every few minutes; Wider moves it further. It never
    leaves title-safe for the controls.
  - **Night dimming:** it dims at the night window.
  - **Scheduled rest:** the screen goes black and the Apple TV is allowed to sleep, so the TV's own
    screensaver or sleep takes over. Any press wakes it.
  - **Breaks:** the board blacks out for each break, then resumes.
  - **When the hub can't be reached:** with "Rest", the board rests after the set time.
  - **Allow the Apple TV screen saver:** on, the system screen saver takes over after its timeout; off, the
    viewer stays on.
  - Note the TV's own panel protection (pixel shift, logo dimming). OLED care can't switch it off (DD23).

## 9. Siri Remote: touch and click paths

- **How:** use each remote you can get:
  - the Siri Remote (1st generation, touch surface);
  - the Siri Remote (2nd or 3rd generation, clickpad and ring);
  - an IR universal remote or the TV's own remote through HDMI-CEC.
- **Pass:**
  - **Swipes and clicks:** on the touch surface, swipes move focus one step at a time and a click selects.
    On the clickpad, the ring's edges move focus and the centre selects; circling the ring doesn't jump
    through a list.
  - **Menu / Back:** goes up one level every time (Viewer → Your panels; a Settings page → Settings → where
    you came from; OLED care → Settings), and never exits from a nested screen. On Your panels, it leaves
    the app.
  - **Waking from rest:** while the viewer rests, the first press only wakes it; it doesn't open the
    controls or act.
  - **Play/Pause:** shows the controls on the viewer.
  - **Long press:** a long press of Select does nothing unexpected (no repeated actions).
  - **TV button:** going Home and back resumes the same screen, and the board updates within 2 s.

## 10. Overscan and the safe area

- **How:**
  1. Turn off Settings › Video and Audio › Calibrate › Zoom and Overscan.
  2. Photograph every screen on a TV with its own overscan on (the TV's default picture size).
- **Pass:**
  - no text or control is cut by the TV;
  - headings, buttons and the chip sit inside the 80 pt (sides) / 60 pt (top and bottom) title-safe area.
    Boards are exempt, because they are full-bleed by design (DD24).
  - **Note arrays:** report whether the outer Note bezels are cut (N28-4, designer).

## 11. The TestFlight internal build and the App Store review checklist

- **How:**
  1. Upload with the **App Store release** workflow (docs/PUBLISHING.md) and add the build to an internal
     TestFlight group.
  2. Install it from TestFlight on both Apple TVs.
  3. Before submitting, go through Apple's App Review checklist.
- **Pass:**
  - **The build:** it processes without warnings (no ITMS errors), and TestFlight installs and launches it
    on both devices. Items 1–10 pass on it.
  - **App Privacy:** the answers match docs/PRIVACY.md. With FiestaBot retired (A9), there's no AI-provider
    data flow.
  - **Age rating:** the questionnaire is answered against server-supplied content.
  - **Listing and media:** the review notes and the reviewer walkthrough are attached (App Store media
    workflow). Screenshots match the current screens. The listing passes the vocabulary guard.
  - **Licences and encryption:** Licenses shows the notices, with the taco credit. Export compliance
    (`ITSAppUsesNonExemptEncryption = NO`) is accepted.
  - **The demo hub:** the review contact can reach a demo hub, or the notes explain the fixture walkthrough.

## 12. The O6 device-name entitlement (once Apple grants it)

- **How:**
  1. Once Apple grants `com.apple.developer.device-information.user-assigned-device-name`, add it to the
     profile and archive.
  2. Rename the Apple TV in Settings › General › About › Name (for example "Living Room").
  3. Sign in with the phone.
- **Pass:**
  - device sign-in shows "This TV will appear as 'Living Room'";
  - the hub's device list and the phone's Displays show "Living Room".
  - Without the entitlement, the honest fallback "This TV will appear as 'Apple TV'" shows (DD3).
- **Record:** whether the entitlement is in the shipped profile.

## 13. O10: the rejected 1.0, or a 1.0.1

- **How:**
  1. In App Store Connect, open the tvOS version that was rejected (build 1.0 (2.1), run 41543961861).
  2. Read the rejection.
  3. Either answer it and resubmit 1.0 with a new build, or remove it from review so that
     `scripts/app-store-release.py` can create 1.0.1.
- **Pass:**
  - the scheduled release no longer stops with "Existing App Store version needs attention: REJECTED";
  - a build from `main` reaches TestFlight;
  - `CHANGELOG.md`'s heading matches the version that ships.

## Results

| Date | Device | tvOS | Build | Item | Pass / fail | Evidence |
|---|---|---|---|---|---|---|
| | | | | | | |
