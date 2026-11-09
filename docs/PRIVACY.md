# FiestaBoard for Apple TV privacy

Effective November 8, 2026.

FiestaBoard for Apple TV is an open-source companion app that connects to a
FiestaBoard hub you choose. It does not include advertising, analytics,
tracking SDKs, or an account service operated by the app developer.

## Your hub and connection

The app sends panel, sign-in and control requests to the FiestaBoard hub
at the address you select or enter. That hub may run on your local network
or at a remote address you configure. Its operator controls its data handling.
The app developer does not receive your board contents, credentials, usage
analytics or tracking data through the native app.

Your hub's address and display preferences are stored on your Apple TV.
Supported hubs issue a revocable TV credential stored in the device's
Keychain. A password entered directly is sent to your hub for sign-in and
is not retained after that credential is issued.
Hubs without TV sign-in use a saved, encrypted password to reconnect: a hub
too old to offer TV sign-in, or one with it turned off. That password is
kept in the Keychain. Plain HTTP connections do not encrypt passwords,
credentials or hub requests in transit; use trusted networks and HTTPS
where your hub supports it.

## Home screen previews

Panel names and static board snapshots are cached on this Apple TV and shared
with its Top Shelf extension so they can appear on the Home screen. No hub
address or sign-in credential is shared with that extension. These caches can
be removed by the system and are cleared when you sign out or forget a hub.

## Removing access

Sign out or forget the hub to remove local credentials and cached previews.
The app also attempts to revoke its TV credential on your hub. If the hub
is offline, revoke this TV on your phone in **Displays › *your TV* › Shown on**,
or in **Account → Signed-in devices** on the hub's web page.
Removing local information does not delete records retained by your hub;
contact its operator or follow its deletion controls.

## Questions and support

Contact the maintainers through [FiestaBoard for Apple TV support](https://github.com/Fiestaboard/fiestaboard-tvos/issues).
GitHub handles information you choose to submit there under its own privacy
policy. Issues are public: do not include passwords, credentials, private
activation codes or sensitive board content.
