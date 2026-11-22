# Mac Hue Control

Control your Philips Hue lights from the Mac menu bar: rooms, zones and single lights, with brightness, colour, white temperature and scenes.

- Talks straight to your Hue Bridge on your home network. No Hue account, nothing goes to the internet.
- Changes made in the Hue phone app or with a wall switch show up straight away.

## Install

```
./build.sh
```

This runs the tests, builds the app, installs it in `/Applications` and opens it. The first time, a window opens to find your bridge. When asked, press the round link button on top of the bridge.

macOS will ask to let the app find devices on your local network. Click **Allow**.

## Use

- Click the light bulb in the menu bar. Each room and zone has an on/off switch and a brightness slider. The arrow next to a name shows its scenes and single lights.
- **Open Hue Control…** opens the full window with colours, white temperature and scenes.
- Settings (the gear) has "Open when I log in" and "Set up the bridge again".
