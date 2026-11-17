# tvOS release handoff — 2026-11-14

The universal TV implementation is integrated on `universal-tv`, but is not yet
release-ready. This handoff records software evidence and the remaining release
gates; it does not replace physical-device validation or authorize publication.

## Source and review evidence

- Audited integration baseline: `f1fc67d8e94b4075d8075ca0a2ac8f0ecf2f5b6c`.
- [PR #34](https://github.com/Fiestaboard/fiestaboard-tvos/pull/34) merged into
  `universal-tv` on November 9. Its reviewed head
  `1df60031b14688d54b654b828f46471e998856e9` has the identical source tree.
- [CI run 42571457246](https://github.com/Fiestaboard/fiestaboard-tvos/actions/runs/42571457246)
  passed `build-and-test`, `Release archive`, and the informational Home Top
  Shelf screenshot job on that PR head. The integration merge SHA itself has
  no check runs: the workflow runs on pull requests and pushes to `main`.
- `main` is still `e84ec8aef3c2071264bbe9ae9bfddca5e073a2fc`; the universal TV
  implementation has not been merged into the release line.
- [Scheduled release run 42724141565](https://github.com/Fiestaboard/fiestaboard-tvos/actions/runs/42724141565)
  failed November 9 with `Existing App Store version needs attention: REJECTED`.
  This is the existing O10 account-owner gate, not a new compilation failure.

## Fresh local validation

Run against the unchanged source baseline above on November 14. Only this
handoff document was untracked at the start. Xcode 27.2, build 27B52, XcodeGen
2.46.0, and tvOS device/simulator SDKs 27.2 are installed.

The following checks passed:

```sh
./scripts/check-layering.sh
swift -module-cache-path /private/tmp/cx-tvready-tvos-swift-cache scripts/check-brand-assets.swift
./scripts/test-simulator-selection.sh
./scripts/test-release-probe-check.sh
python3 scripts/test-app-store-release.py
ruby scripts/test-fastlane-release.rb
node --test scripts/insets/tests/*.test.mjs
node scripts/insets/check-insets.mjs
node --test scripts/vocabulary/tests/*.test.mjs
node scripts/vocabulary/check-vocabulary.mjs
node scripts/tokens/generate-swift.mjs --check
node --test scripts/tokens/tests/*.test.mjs
npm ci --prefix scripts/parity --no-audit --no-fund --cache /private/tmp/cx-tvready-tvos-npm
npm test --prefix scripts/parity
python3 scripts/test-recording-pacing.py
bash scripts/test-demo-video-export.sh
```

All 16 commands exited 0. Counts: release planner 17 tests; Fastlane 3 tests / 8
assertions; inset guard 6; vocabulary 19; token bridge 8; parity comparer 12;
recording pacing 4. Brand assets passed using a writable
Swift module cache. Video export retained the original and produced 60 distinct
1080p60 frames. The video test is not executable in Git, so it was invoked with
`bash`.

The production Foundation OLED policy and its actual `OLEDCareTests` also
compiled and passed on macOS: **13 tests, 0 failures**. This used
`scripts/test-oled-core.sh` with only its temporary-directory prefix changed to
`/private/tmp/cx-tvready-tvos-oled.XXXXXX` and its working directory made explicit.
It does not exercise the tvOS UI or simulator integration.

Native app validation remains blocked by the environment:

- `xcodegen generate` could not write generated `Info.plist` in the worktree
  (`Operation not permitted`, exit 1). The file was absent and the directory
  had normal permissions and no file flags. Generation **passed** from a
  `git archive HEAD` source copy under `/private/tmp/cx-tvready-tvos-source-20261114`.
- The worktree unsigned archive exited 66 because no project had been generated.
  Archiving the generated project in the isolated source copy progressed to
  Swift package resolution, then exited 74: the manifest compiler could not
  write diagnostics under `~/Library/Caches/org.swift.swiftpm` (`Operation not
  permitted`). A retry with private package, SwiftPM module and Clang module
  caches produced the same diagnostics-path denial. Neither attempt compiled
  the app or produced a usable archive. The final command was:

  ```sh
  SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/cx-tvready-tvos-swiftpm-cache \
  xcodebuild -project FiestaBoardTV.xcodeproj -scheme FiestaBoardTV \
    -configuration Release -destination 'generic/platform=tvOS' \
    -derivedDataPath /private/tmp/cx-tvready-tvos-dd \
    -clonedSourcePackagesDirPath /private/tmp/cx-tvready-tvos-packages \
    -packageCachePath /private/tmp/cx-tvready-tvos-package-cache \
    archive -archivePath /private/tmp/cx-tvready-tvos-FiestaBoardTV.xcarchive \
    CODE_SIGNING_ALLOWED=NO \
    CLANG_MODULE_CACHE_PATH=/private/tmp/cx-tvready-tvos-clang-cache
  ```

- `xcrun simctl list devices available` failed to connect to CoreSimulator
  (exit 1, `Connection refused`; simulator log access was denied). No simulator tests,
  new screenshots, accessibility audits, or native parity captures ran locally.
  No shared simulator was booted, reset or deleted.

These are environment failures, not evidence of an app compilation failure.
Local logs are retained at `/private/tmp/cx-tvready-tvos-verified-20261114`
(`results.json`, numbered script logs, `19-temp-xcodegen.log`, the two temporary
archive logs, and `22-oled-core.log`); they are temporary evidence, not shipped assets.
The local checks do not establish native app correctness or replace CI.
The docs pull request must receive fresh required CI checks before integration.

## Prepared release inputs

| Input | Repository source | Still needed |
|---|---|---|
| Version and release notes | `project.yml`, `CHANGELOG.md`, `fastlane/Fastfile` | Choose the corrected version after O10; the planner supplies both targets' matching version/build at upload. Do not bump a speculative store version here. |
| Listing, privacy and licences | `fastlane/metadata/en-US`, `docs/PRIVACY.md`, `Resources/PrivacyInfo.xcprivacy`, `Resources/THIRD_PARTY_NOTICES.txt` | Account-holder declarations and verification of the published policy URL. Taco permission wording is already present. |
| Signing and upload | `Config/Signing.local.xcconfig.example`, `Config/ExportOptions-TestFlight.plist`, `.github/workflows/app-store-release.yml` | Owner signing profiles/certificates, signed validation and TestFlight installation; see PUBLISHING. |
| Screenshots and reviewer video | `.github/workflows/app-store-media.yml`, `scripts/capture-app-store-media.sh`, `scripts/prepare-app-store-media.py` | Fresh captures of the intended release build; this pass generated no app media. |

The upload workflow already accepts `ASC_KEY_P8`, `ASC_KEY_ID`, `ASC_ISSUER_ID`,
`APPLE_TEAM_ID`, `APPLE_DISTRIBUTION_P12_BASE64`, `APPLE_DISTRIBUTION_P12_PASSWORD`,
`APPLE_APP_PROFILE_BASE64` and `APPLE_TOPSHELF_PROFILE_BASE64`. Their names are
documented inputs; this pass did not inspect secret values or verify signing access.
Keep `APP_STORE_RELEASE_ENABLED` under owner control. A `plan` workflow run still
needs account credentials; it is not a credential-free local check.

## Remaining release gates

1. Obtain fresh green `build-and-test` and `Release archive` results on the
   intended source. Review Home Top Shelf evidence as well, even though its job
   is informational. Keep the resulting archive, test results and parity artifacts.
2. Complete the fresh batched Fable parity/review gate using the saved program
   screenshot references and current captures. Do not open the milestone PR
   into `main` until that gate is ready. Comparer unit tests above are not a
   visual parity review.
3. Complete and record [HARDWARE-CHECKLIST.md](HARDWARE-CHECKLIST.md) on Apple TV
   HD and 4K as applicable: VoiceOver, glass/contrast, Top Shelf status text,
   performance and sharpness, cold start, 24-hour soak, OLED care, Siri Remote,
   overscan, discovery, legacy migration and Increase Contrast. All sections
   1–17 still require actual result entries where applicable. Simulator
   evidence cannot satisfy these hardware checks.
4. Resolve O10 in App Store Connect: inspect the rejection and choose the
   appropriate corrected submission/version. Preserve the automated release
   planner's stop for rejected versions.
5. After the review gate, prepare the milestone integration into `main` for the
   owner merge required by the Phase 4 plan. Verify required checks on the
   resulting release commit; the upload planner checks the exact `main` SHA.
6. Follow [PUBLISHING.md](PUBLISHING.md) for signing, both targets' App Group,
   signed archive validation, privacy report, TestFlight installation and reviewer
   media. Update privacy and age-rating answers for FiestaBot's retirement and
   review content rights with the account holder. An internal-only TestFlight
   build cannot later be submitted publicly.
7. O6 device-name entitlement remains an owner capability decision. Keep the
   entitlement absent until Apple grants it and the profiles support it; the
   existing honest `Apple TV` fallback permits shipping without an assigned name.

The checklist's results table must contain actual device evidence before any
hardware-complete claim. No store submission, release-line merge, signing
configuration change, or schedule change is part of this handoff.
