# Security policy

Pawse is an offline macOS menu bar app. It has no accounts, no server and makes **no network requests**.
Everything it stores (settings, water/habit history, screen-time totals) stays on your Mac in
`~/Library/Preferences/com.swalahu.pawse.plist` and `~/Library/Application Support/Pawse/`.

It reads only *how long ago* you last pressed a key or moved the mouse (to measure active screen time).
It never records what you type, which apps you use, or anything on screen.

## Reporting a vulnerability

Please **do not open a public issue**. Use GitHub's private reporting: open the repository's
**Security** tab and choose **Report a vulnerability**. You can expect an acknowledgement within a few days.

Supported version: the latest release.
