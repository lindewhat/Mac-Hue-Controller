# Mac Hue Control

## What this app does
A macOS menu bar app for controlling Philips Hue lights directly over the local network. For the owner's own home first; built so others can install it too. It deliberately does not do bridge setup, adding lights, editing rooms/scenes or remote (away-from-home) control: the Hue phone app does those.
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
- Rules the owner decided live in HueKit and are tested: room adjustments (`RoomAdjust`: off lights stay off, nothing switches on), scenes (`SceneApply`), light order (`LightOrder`). `HueStore` only applies their plans.
- `Sources/MacHueControl`: the SwiftUI app. `HueStore` holds the live state and sends changes; `MenuBarView`, `MainWindow`, `SetupView`, `SettingsView`; shared controls in `Controls.swift`.
- Bundle id: `com.lindewhat.mac-hue-control`. Info.plist in `Resources/`.
- App icon: `Resources/AppIcon.icns`, drawn by `swift scripts/make-icon.swift` (rerun only to change the design).

## Key decisions (and why)
- Swift Package + build.sh, no hand-made Xcode project (same as Mac Sonos Control): small, scriptable, no third-party dependencies.
- SwiftUI `MenuBarExtra(.window)` for the panel, not an `NSMenu`: views update in place, so nothing is rebuilt mid-click (the Sonos menu needed fixes for exactly that).
- Clicks are never dropped: no "busy" guards. Every change goes through one ordered pipe into `CommandQueue`, which keeps one lane per light/room/scene, sends the first command at once and merges later ones (newest value wins, nothing asked for is lost). Gaps: ~110 ms per light, ~1 s per room/zone (the bridge's limits). A "busy" answer (429) is retried.
- Switches decide from the real state in the store (`!isOn`), never from the control's own value. A room is "on" if any light in it is on; no half-on state.
- Sliders never jump under the finger: while dragging they show the user's value and send whole numbers only; after release the store's shield keeps the value until the bridge has caught up.
- Never crash on bridge data: no force-unwraps, a time limit on every request, lenient decoding (one odd resource never hides the rest), a plain message for every failure.
- The bridge is the source of truth: optimistic updates, then live events confirm; any failed change re-reads everything; the panel re-reads when opened if older than 5 s; the stream reconnects with growing pauses and re-reads after reconnecting.
- Brightness, warmth and colour never switch a light on or off; only the on/off switches do (`RoomAdjust`, tested). For a room they change only the lights that are on; if the whole room is off they change every light's setting but leave them off (the bridge stores it for when they're turned on; verified on a real bridge). Lit lights get per-light commands; a big room (>4 lights) that is entirely on gets one `grouped_light` command. All light commands share one ~10/s budget in `CommandQueue`.
- Scenes (`SceneApply`): a scene changes only a light's look (colour, white warmth or gradient). It never changes brightness and never switches a light on or off, whatever the scene says (this changed from "the scene's settings including brightness" to "look only"; tested, including that the sent JSON has no `dimming` or `on`). The bridge's own scene recall switches every light on and sets brightness, so the app instead reads the scene's per-light look and sends it only to lights that are on; colours are fitted to each light's gamut, white-only bulbs get only warmth, gradient lights get the gradient. If the whole room is off, the look is stored on the lights but they stay off. Scenes with no colour, warmth or gradient (brightness or on/off only) have nothing to apply, so they aren't offered (`Scene.changesLook`), and a scene that changes nothing in a room isn't marked as chosen. Because the bridge then doesn't mark the scene active, the store remembers the chosen scene per room (`chosenScene`) until a light there is changed in the app; not kept across restarts. Effects (candle, fire) and moving "dynamic" scenes aren't reproduced. Verified on a real bridge.
- Shields (HueStore): for 3 s after a light is changed here, the bridge's reports for it are held back, then the latest one is applied. This stops switches and sliders flicking back to in-between values the bridge reports late.
- Light order (`LightOrder`): natural numbers/letters, and lights that differ only by a position word follow the position (up→middle→down, left→middle→right, front→back, first→second, one→two; English and Danish). Renaming a light re-reads so it re-sorts.
- Each light is its own observable `LightState`, so a change redraws only the rows showing that light.
- The panel looks like a native menu (Wi-Fi menu as reference): macOS draws its see-through background itself because build.sh stamps the real SDK version into the program (SwiftPM stamps the 15.0 minimum otherwise, which gives the older, nearly solid look); the app adds no background or transparency code of its own. Plain rows, thin inset separators, small grey section headings, menu-style rows at the bottom. `open -a "Mac Hue Control" --args --panel-preview` shows the panel in a normal window for checking its look (the real menu bar isn't capturable).
- Security: the bridge has its own certificate. `BridgeTrust` remembers its fingerprint at pairing (pressing the link button proves it's the right bridge) and accepts only that certificate, only from the bridge's address. If it changes, the app asks to set up again.
- The app key lives in the Keychain. Bridge id/name/address/certificate fingerprint in UserDefaults (`savedBridge`).
- If the bridge's address changes (router gave it a new one), the app searches for the same bridge id and reconnects.
- Discovery always finishes: its timers hold the search strongly (the Sonos search once never finished because of `[weak self]`). Tested.
- Window size: each time the window opens, `ControlView` lays out every room/zone out of sight (colour wheel showing, 760 pt content width), takes the tallest, and sizes the window to fit it exactly without scrolling (capped to the screen, top edge kept). Only once per opening, so a size the user picks afterwards stays.
- Dock icon only while the window is open (activation policy switches); otherwise menu bar only (`LSUIElement`).
- build.sh assembles the app in $TMPDIR (not the Desktop folder): iCloud/Finder markings there break code signing. It signs with a stable identity (Apple Development) so the Keychain doesn't ask again after every rebuild, and verifies the signature after installing.
- Privacy: only LAN traffic to the bridge. No analytics, no cloud calls (the meethue.com discovery service is deliberately not used), no logging of room/light names or IPs.
- Logging (`Log` in HueKit): failures and every warning the user is shown go to `~/Library/Logs/Mac Hue Control/Mac Hue Control.log` (plain text, rotated at about 1 MB to `.log.1`, never in the repo). **Read it first when something breaks.** No personal data ever: no addresses, bridge ids, names or resource ids; lights/rooms/scenes appear as per-run labels ("light 3"), errors by kind and code only (system error texts can contain the bridge's address). A connection problem is logged once until it is fixed, not on every retry. `open -a "Mac Hue Control" --args --verbose` adds a line per request (DEBUG); leave it off normally. Tested in `LogTests`, including that a made-up id and address never reach the file.
- Live updates use a long-running stream, for which macOS asks the per-request certificate question; `BridgeTrust` answers it the same way as the per-session one. Without that the stream was refused (-1202) and the app silently re-read everything every second instead (found through the log, fixed; verified on the real bridge).
- Sharing later (not done): paid Apple Developer Program, Developer ID signing, Hardened Runtime, notarization.

## If someone asks you to install this app
Follow the "For Claude: installing this for someone" section of `README.md`. It is the single source of truth; keep it in step with `build.sh`.

## Must work on any Mac
- Apple Silicon, macOS 15 or newer, Xcode installed (build.sh checks all three and says what to do).
- Nothing tied to one home: no hard-coded bridge address, room or light names. The bridge is found automatically, or its address typed in.
- First launch walks through finding the bridge and pressing its link button; Local Network permission denied, bridge not found and bridge unreachable each get a plain message and a button. Never fails silently.
- Works with any mix of Hue lights: white-only bulbs, colour bulbs, gradient strips and smart plugs (on/off only).
