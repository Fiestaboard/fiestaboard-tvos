# FiestaBoard for Apple TV support

FiestaBoard connects your Apple TV to a FiestaBoard server, commonly hosted
on a Raspberry Pi. Create panels in the server's web interface first. Virtual
panels do not require a physical split-flap display.

1. Connect the Apple TV and server to the same network, or provide a reachable
   HTTPS server address.
2. Select your discovered board or enter its address. A bare address uses
   port 4420 by default.
3. Approve TV sign-in by scanning the QR code or entering the displayed code
   in your board's web interface. Direct password sign-in is also supported.
4. Pick a panel. Settings separates preferences for this Apple TV from panel
   settings shared with other viewers.

If discovery finds nothing, enter the server's IP address manually. Docker
bridge networking may not advertise a discoverable Bonjour service. Check
that the server is running and port 4420 is reachable.

For Home screen previews, put FiestaBoard in the top row and open the app to
refresh its panel snapshots. The app cannot automatically launch after an
Apple TV power cycle.

FiestaBot requires a compatible server, a configured AI provider and an
eligible password-based connection. It is unavailable with scoped TV sign-in.

[Report a problem or ask for help](https://github.com/Fiestaboard/fiestaboard-tvos/issues).
Include the app/server versions and steps to reproduce the problem. Issues
are public; omit passwords, credentials, private codes and sensitive content.

[FiestaBoard setup documentation](https://fiestaboard.app/docs/intro/)
and [Apple TV app privacy](PRIVACY.md).
