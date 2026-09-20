# Publishing FiestaBoard for Apple TV

The app bundle ID is `com.fiestaboard.tv`. Set `DEVELOPMENT_TEAM` in a local
Xcode configuration or signing override before creating a signed archive. Do
not commit a team ID or signing credentials. The unsigned Release archive in
CI checks compilation and bundle assembly; it is not an App Store upload.

The Top Shelf extension has bundle ID `com.fiestaboard.tv.topshelf`. Register
the App Group `group.com.fiestaboard.tv` for both bundle IDs in the Apple
Developer portal, then refresh their provisioning profiles. Both targets use
`Config/AppGroup.entitlements`. The extension reads locally cached board
images; it does not receive the board address or sign-in credential.

Use **FiestaBoard for Apple TV** as the App Store name and **Your panels, on
your TV** as the subtitle. App Review may reject the platform wording under
guideline 5.2.5. If it does, use **FiestaBoard** and keep the subtitle. The
display name is set in `project.yml` (`CFBundleDisplayName`).

The app collects no data. App Privacy answers are all “No.” The board address
and password stay on the device; the password is stored in Keychain. Network
traffic goes only to the user's own FiestaBoard on the local network. The
`NSLocalNetworkUsageDescription` in `project.yml` explains this access.

Include a reachable demo FiestaBoard address in App Review notes or provide a
video of the connection, sign-in, panel list, viewer, and settings flow. A
reviewer is unlikely to have a board on their network. Also provide current
screenshots from a tvOS simulator and verify the layered app icon and Top
Shelf assets in the signed archive before upload.

After local testing, measure the 45 × 18 animated board on real Apple TV
hardware. The simulator cannot establish the 60 fps performance checkpoint.
