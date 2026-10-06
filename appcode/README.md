# Trace

Set where your iPhone says it is. Tap the map, search a place or type coordinates, or follow a route. Trace sets the position through Apple's **developer location service**, so Maps and other apps see it system-wide, not just a Wi‑Fi lookup that outdoor GPS would overwrite.

## Features

- Spoof any place: tap the map, search, or paste coordinates
- Joystick for walking, running, cycling or driving, with natural speed variation
- Routes on real roads and footpaths (MapKit), drawn paths, and GPX import and export
- Favourites, recents and saved routes
- Background keep-alive, with an alert if a live session drops
- Fully on-device: no analytics, nothing uploaded

## Install

See [SETUP.md](SETUP.md) for the full steps. The latest IPA is published on [Releases](https://github.com/xerooae/trace/releases/latest).

Bundle ID: `com.xerooae.trace` · URL scheme: `trace://`

### LiveContainer

File pickers often don't work inside LiveContainer. Use one of these:

1. Long-press **Trace** → **Settings** → enable **Fix File Picker**, then try Import again.
2. Share the pairing file **into LiveContainer → Trace**.
3. Copy the RPPairing file's contents, then in Trace use **Paste from clipboard** (first run or Settings › Pairing).

## How it works

Trace uses the MIT-licensed [idevice](https://github.com/jkcoxson/idevice) FFI to talk to Apple's DVT location simulation over an on-device developer tunnel, the same mechanism Xcode uses.

- **iOS 27:** Settings › Pairing › **Pair on this iPhone** advertises a pairable host. Confirm the six-digit code under Settings › Privacy & Security › Developer Mode › Pair with Host. No computer needed.
- **iOS 26:** import an **RPPairing** file once, made with [idevice_pair](https://github.com/jkcoxson/idevice_pair/releases).

Also install **[LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044)** (a loopback tunnel, default `10.7.0.1`).

Start your first spoof on Wi‑Fi. After that it keeps working on cellular.

Some games run their own location checks and reject developer-set positions. That's expected with this method: Trace changes what the system reports and doesn't modify other apps.

## Build

The IPA is built in CI on every push to `main` (`.github/workflows/build.yml`), unsigned for LiveContainer to sign.

To build locally you need a Mac with Xcode 26 or later and an Apple Developer account (free or paid):

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
2. Set your Team ID in `project.yml` (`DEVELOPMENT_TEAM`), or pick your team in Xcode under Signing & Capabilities.
3. Generate and open:

```bash
xcodegen generate
open Trace.xcodeproj
```

Or build from the command line:

```bash
xcodegen generate
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Release \
  -destination 'generic/platform=iOS' DEVELOPMENT_TEAM=YOUR_TEAM_ID build
```

## Licence

MIT. Trace is based on [Locus](https://github.com/ChrisMack32/Locus) (MIT), and `Vendor/idevice` contains the idevice FFI (MIT). See [LICENSE](LICENSE).
