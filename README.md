# Mac Hue Control

Control your Philips Hue lights from the Mac menu bar: rooms, zones and single lights, with brightness, warmth, colour and scenes.

- Talks straight to your Hue Bridge on your home network. No Hue account needed, and nothing goes to the internet.
- Changes made in the Hue phone app or with a wall switch show up straight away.
- Gentle by design: brightness, warmth, colour and scenes only change lights that are already on. Lights that are off stay off until you switch them on.

## Easiest way: let Claude install it

Open Claude Code (or the Code tab in the Claude desktop app) and say:

> Help me install https://github.com/lindewhat/Mac-Hue-Controller

Claude checks your Mac, does the technical steps itself, and tells you, one at a time, the few things only you can do (such as clicking **Allow** and pressing the button on your Hue Bridge). If you'd rather do it yourself, follow **Install** below.

## Requirements

- A Mac with Apple Silicon (M1 or newer) running macOS 15 (Sequoia) or newer. So far it has been used on macOS 27 with one home's lights.
- A **Philips Hue Bridge, square model** (the second generation, or newer), on the same home network as your Mac. The original round bridge doesn't work with this app.
- Rooms and lights set up in the Hue phone app. This app controls them; it doesn't set them up.
- **Xcode**, Apple's free developer tool, to build the app. It's a large download from the App Store.
- Optional: a free Apple Development certificate (step 2), so macOS doesn't ask about the Keychain again after every update.

## Install

There's no ready-made download yet: you build the app on your own Mac. It takes a few minutes and one command.

### 1. Install Xcode (once)
1. Open the **App Store**, search for **Xcode**, and click **Get**. The download is large, so give it time.
2. Open Xcode once. If it asks you to accept a licence or install extra parts, accept. Then you can quit it.

### 2. Optional: a free signing certificate (once)
Without it the app still works, but macOS may ask "Mac Hue Control wants to use your keychain" after every update.
1. Open Xcode, then choose **Xcode > Settings > Accounts**.
2. Click **+**, choose **Apple ID**, and sign in.
3. Select your account, click **Manage Certificates**, click **+** and choose **Apple Development**. Close the window.

### 3. Download this project
On this page, click the green **Code** button, then **Download ZIP**. Double-click the ZIP to unpack it.

### 4. Build and install
1. Open **Terminal**: press Cmd+Space, type "Terminal" and press Return. It's a window where you type commands.
2. Type `cd ` (with a space after it), drag the unpacked folder into the Terminal window, and press Return. This tells Terminal which folder to work in.
3. Type `./build.sh` and press Return.

It checks your Mac, runs its own tests, builds the app, puts it in your **Applications** folder and opens it. If something is missing it stops and tells you exactly what to do.

### 5. Connect to your bridge
1. When macOS asks **"Mac Hue Control" would like to find devices on your local network**, click **Allow**. The app needs this to find your bridge.
2. A window opens and finds your bridge. When it says **Press the round link button on top of your bridge**, press that button. You have 3 minutes.
3. Your rooms appear. That's it.

If no bridge is found, type its address in the box below. You'll find it in the Hue app under **Settings > Bridges**, then tap your bridge (it looks like `192.168.1.20`).

## Use

- Click the **light bulb** in the menu bar. Each room and zone has an on/off switch and a brightness slider. Click the arrow next to a name to see its scenes and single lights.
- **Open Hue Control…** opens a window with colours, white warmth and scenes for each room, and each light's own controls (click a light's colour dot).
- **Settings…** has "Open when I log in" and "Set up the bridge again".

The menu bar icon is a filled bulb when any light is on, an outline when all are off, and a warning triangle when something needs your attention.

## Update

People who already installed the app don't get changes automatically: each person has their own copy, and nothing updates it until they ask. To update:

1. Open Terminal in the project folder (`cd `, then drag the folder in, then Return), run `git pull`, then `./build.sh`. This only works if the project was installed with `git clone`, which is what the Claude install does.
2. Or say to Claude: "Update Mac Hue Control".

If you installed from a downloaded ZIP, download the new ZIP and run `./build.sh` in it again. Your bridge connection is kept.

## For Claude: installing this for someone

If a person asks you to help install this app, follow this. They may not be technical. Do every step you can yourself, explain in plain words, and give them **one** human step at a time. Never ask for their password; if a command needs `sudo`, show it and let them run it.

1. **Check the Mac.** `uname -m` must print `arm64`. `sw_vers -productVersion` must be 15 or higher. If either fails, stop and explain plainly that this Mac can't run the app.
2. **Check Xcode.** `xcodebuild -version` must succeed. If it doesn't, ask them to install Xcode from the App Store and open it once (step 1 above), and wait until they say it's done. If Xcode is installed but the check still fails, show them `sudo xcode-select -s /Applications/Xcode.app` to run themselves.
3. **Ask about the bridge.** Confirm they have a square Hue Bridge set up with the Hue phone app, on the same network as this Mac. A round (first-generation) bridge won't work.
4. **Get the code.** `git clone https://github.com/lindewhat/Mac-Hue-Controller.git ~/Mac-Hue-Controller`, then `cd` into it and read `CLAUDE.md`.
5. **Optional signing certificate.** Run `security find-identity -v -p codesigning`. If it finds no "Apple Development" identity, explain step 2 above and offer it as optional. Without it, macOS asks about the Keychain after each update.
6. **Build and install.** Run `./build.sh` (it takes a few minutes; run it in the background and say so). It ends with "Installed and verified" and opens the app.
7. **Permissions and pairing, one at a time.** First, macOS asks to find devices on the local network: they click **Allow**. Then the window shows "Press the round link button on top of your bridge": they press it (they have 3 minutes).
8. **Test with them.** Ask them to click the light bulb in the menu bar and flip one room's switch, and to confirm the real lights changed.

**To update an existing install** (the person says "update Mac Hue Control"): `cd ~/Mac-Hue-Controller`, run `git pull`, then `./build.sh`, and tell them it takes a few minutes. If `git pull` reports local changes, don't discard them; explain and ask. If they installed from a ZIP there's no git history: download the new ZIP and build from it.

If something fails:

| What they see | Cause and fix |
|---|---|
| "Cannot continue: Xcode is not ready" | Xcode is missing or was never opened. Install it, open it once, run `./build.sh` again. |
| "Cannot continue: some tests failed" | The downloaded code is broken. Nothing was installed. Report it to the project owner. |
| "No Hue Bridge found" | Mac and bridge on different networks, Local Network permission not allowed, or a round bridge. Check System Settings > Privacy & Security > Local Network, or type the bridge's address from the Hue app. |
| "The link button on the bridge wasn't pressed in time" | Click **Try again**, then press the bridge's button within 3 minutes. |
| "Can't reach your Hue Bridge right now" | The bridge is off or on another network. The app reconnects by itself when it's back, and finds the bridge again if its address changed. |
| "Set it up again" / "certificate changed" | The bridge was reset or replaced. Click **Set up again…** and press the link button. |
| macOS asks about the Keychain after every update | No signing certificate. Do step 2 above (optional). |

## For developers

Run the tests with `swift test`. Read `CLAUDE.md` for the layout and the reasons behind the main decisions. All Hue logic lives in `Sources/HueKit` (no UI, unit-tested); the app is in `Sources/MacHueControl`.

## Licence

MIT: you are free to use, copy, change and share this software, as long as the licence text stays with it. See `LICENSE`.
