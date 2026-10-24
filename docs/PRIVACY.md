# FiestaBoard for Apple TV privacy

Effective October 24, 2026.

FiestaBoard for Apple TV is an open-source companion app that connects to a
FiestaBoard server you choose. It does not include advertising, analytics,
tracking SDKs, or an account service operated by the app developer.

## Your board and connection

The app sends panel, sign-in and control requests to the FiestaBoard server
at the address you select or enter. That server may run on your local network
or at a remote address you configure. Its operator controls its data handling.
The app developer does not receive your board contents, credentials, usage
analytics or tracking data through the native app.

Your board address and display preferences are stored on your Apple TV.
Supported servers issue a revocable TV credential stored in the device's
Keychain. A password entered directly is sent to your board for sign-in and
is not retained after that credential is issued. Older servers can require
a password retained in the Keychain to reconnect. Plain HTTP connections do
not encrypt passwords, credentials or board requests in transit; use trusted
networks and HTTPS where your server supports it.

## Optional AI features

Where supported and available to your connection, FiestaBot sends conversation
and relevant board content through your FiestaBoard server to the AI provider
configured on that server. That provider may be a third party and has its own
privacy and retention policies. Review the server's provider configuration
before sending personal or sensitive information. The native app does not
embed an AI provider SDK or supply the developer's AI account.

Scoped TV credentials cannot use FiestaBot. On eligible connections, native
chat history stays in memory until a new chat, sign-out or app restart; your
server and AI provider may retain their own records. Siri dictation follows
Apple's system keyboard settings and privacy policy.

## Home screen previews

Panel names and static board snapshots are cached on this Apple TV and shared
with its Top Shelf extension so they can appear on the Home screen. No server
address or sign-in credential is shared with that extension. These caches can
be removed by the system and are cleared when you sign out or forget a board.

## Removing access

Sign out or forget the board to remove local credentials and cached previews.
The app also attempts to revoke its TV credential on your server. If the board
is offline, revoke access in **Account → Signed-in devices** on the server.
Removing local information does not delete records retained by your server or
AI provider; contact their operator or follow their deletion controls.

## Questions and support

Contact the maintainers through [FiestaBoard for Apple TV support](https://github.com/Fiestaboard/fiestaboard-tvos/issues).
GitHub handles information you choose to submit there under its own privacy
policy. Issues are public: do not include passwords, credentials, private
activation codes or sensitive board content.
