# Mac Hue Control

## What this app does
A macOS menu bar app for controlling Philips Hue lights directly over the local network.
- Menu bar panel: every room and zone with an on/off switch and brightness slider; open one to see its scenes and single lights.
- Window ("Open Hue Control…"): rooms/zones sidebar; detail with switch, brightness, colour wheel / white temperature, scenes, and each light (click its colour dot for colour/white).
- First launch: the window opens by itself to find the bridge and pair (press the link button).
- Talks only to the Hue Bridge (Hue API v2 "CLIP", HTTPS on the LAN; bridge found via Bonjour `_hue._tcp` or a typed IP). No Hue account, no cloud.
- Live: the bridge's event stream keeps the app in step with the Hue phone app and wall switches.
- One bridge. Unreachable bridge / Local Network off / bridge forgot us: clear message with the right button. Never crash.

## Build and install (one command)
`./build.sh` runs tests, builds, signs, installs to /Applications and launches. `./build.sh --no-run` skips launching.
Tests only: `swift test`.

## Layout
- `Sources/HueKit`: all Hue logic, no UI, unit-tested: discovery, pairing, certificate trust, Keychain, models, client, event-stream parser, command queue, topology (rooms/zones -> lights), colour maths.
- `Sources/MacHueControl`: the SwiftUI app. `HueStore` holds the live state and sends changes; `MenuBarView`, `MainWindow`, `SetupView`, `SettingsView`; shared controls in `Controls.swift`.
- Bundle id: `com.lindewhat.mac-hue-control`. Info.plist in `Resources/`.
- App icon: `Resources/AppIcon.icns`, drawn by `swift scripts/make-icon.swift` (rerun only to change the design).

## Key decisions (and why)
- Swift Package + build.sh, no hand-made Xcode project (same as Mac Sonos Control): small, scriptable, no third-party dependencies.
- SwiftUI `MenuBarExtra(.window)` for the panel, not an `NSMenu`: views update in place, so nothing is rebuilt mid-click (the Sonos menu needed fixes for exactly that).
- Clicks are never dropped: no "busy" guards. Every change goes through one ordered pipe into `CommandQueue`, which keeps one lane per light/room/scene, sends the first command at once and merges later ones (newest value wins, nothing asked for is lost). Gaps: ~110 ms per light, ~1 s per room/zone (the bridge's limits). A "busy" answer (429) is retried.
- Switches decide from the real state in the store (`!isOn`), never from the control's own value. A room is "on" if any light in it is on; no half-on state.
- Sliders never jump under the finger: while dragging they show the user's value; after release they hold it up to 1.5 s until the bridge confirms.
- The bridge is the source of truth: optimistic updates, then live events confirm; any failed change re-reads everything; the panel re-reads when opened if older than 5 s; the stream reconnects with growing pauses and re-reads after reconnecting.
- Room brightness/colour go to the room's `grouped_light` (absolute values, so every light gets the same level).
- Security: the bridge has its own certificate. `BridgeTrust` remembers its fingerprint at pairing (pressing the link button proves it's the right bridge) and accepts only that certificate, only from the bridge's address. If it changes, the app asks to set up again.
- The app key lives in the Keychain. Bridge id/name/address/certificate fingerprint in UserDefaults (`savedBridge`).
- If the bridge's address changes (router gave it a new one), the app searches for the same bridge id and reconnects.
- Discovery always finishes: its timers hold the search strongly (the Sonos search once never finished because of `[weak self]`). Tested.
- Dock icon only while the window is open (activation policy switches); otherwise menu bar only (`LSUIElement`).
- build.sh assembles the app in $TMPDIR (not the Desktop folder): iCloud/Finder markings there break code signing. It signs with a stable identity (Apple Development) so the Keychain doesn't ask again after every rebuild, and verifies the signature after installing.
- Privacy: only LAN traffic to the bridge. No analytics, no cloud calls (the meethue.com discovery service is deliberately not used), no logging of room/light names or IPs.
- Sharing later (not done): paid Apple Developer Program, Developer ID signing, Hardened Runtime, notarization.
