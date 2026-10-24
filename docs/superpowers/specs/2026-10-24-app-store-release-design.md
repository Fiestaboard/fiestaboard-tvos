# Weekly App Store releases

The user selected weekly public releases from tested `main`, skipping unchanged
app sources and an active Apple review, with automatic release after approval.
Apple still reviews every public version. A manual run supports first-release
uploads and deliberate submission once the initial listing is ready.

## Approaches

- Weekly public releases (selected): batch tested app changes, submit through
  Fastlane, and let Apple release approved versions.
- Weekly TestFlight uploads: keep public submission manual; not selected.
- Tagged releases: require an explicit release tag; not selected.

Use existing GitHub Actions and Fastlane rather than migrating to Xcode Cloud
or implementing Apple's upload and submission lifecycle from scratch. Jev's
advisory comparison supported this choice. Implementation details below are
the builder's choices within the selected behavior.

## Release behavior

Run Mondays at 16:00 UTC and by manual dispatch. Verify `build-and-test` and
`Release archive` succeeded for the exact selected `main` commit. The Home UI
job remains informational. Compare app-source changes with the last successful
submission tag; documentation-only changes do not trigger a new version.
Serialize releases. Skip while a version is in review or awaiting release;
stop for rejected versions that require attention. Reuse the initial 1.0 draft;
increment the patch component for later releases. Generate build numbers in CI
without committing version bumps. Record submitted commits with release tags.

Import a distribution identity and both tvOS profiles into an ephemeral
keychain. Keep the API key, certificate and profiles in encrypted GitHub
secrets. Export for public App Store distribution, never internal-only
TestFlight. Remove credentials and the keychain on every exit.

## Listing and first release

Maintain English metadata and factual privacy/support documents in the repo.
Generate current screenshots and a real application walkthrough video using
the UI test fixture server. Explain in review notes that real deployments use
a locally hosted FiestaBoard server, commonly a Pi; the video demonstrates the
companion app without granting access to a user's network.

Do not guess privacy, content rights or age-rating declarations. The first
public submission remains gated until its listing, review video, declarations
and required hardware acceptance checks are complete. Upload-only manual runs
can prepare a build without submitting it. A repository variable enables weekly
public submission after first-release readiness has been established.
