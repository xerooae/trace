# Trace: install and first move

## 1. Sideload the IPA

Install the latest IPA from [Releases](https://github.com/xerooae/trace/releases/latest) (or build from source) with LiveContainer, Feather, SideStore, AltStore or Sideloadly.

Bundle ID: `com.xerooae.trace`

### LiveContainer

File pickers often break inside LiveContainer. Do one of these:

1. Long-press **Trace** in LiveContainer → **Settings** → enable **Fix File Picker**, then try Import again.
2. Share or open the pairing file **into LiveContainer → Trace** (iOS share sheet).
3. Copy the RPPairing file's contents, open Trace → **Paste from clipboard** (first run or Settings › Pairing).

## 2. Account

On first launch, create an account with Sign in with Apple (signed builds only) or your email. For now the account lives on this iPhone and every account has full access.

## 3. Pairing

### On iOS 27, no computer

1. In first run, or Settings › Pairing › **Pair on this iPhone**, tap **Start pairing**.
2. Allow **Local Network** (and Location and Notifications if asked).
3. Leave Trace running. Go to **Settings › Privacy & Security › Developer Mode › Pair with Host**.
4. Pick **Trace** → **Pair**.
5. Enter your **iPhone passcode** first.
6. At the second prompt, type the **six-digit code** Trace shows (it's also sent as a notification).
7. Done: the pairing is saved on this iPhone.

### On iOS 26

1. On a computer, download [idevice_pair](https://github.com/jkcoxson/idevice_pair/releases).
2. Plug in your iPhone, unlock it and tap Trust.
3. Make an **RPPairing** file (not a lockdown or SideStore `.mobiledevicepairing` file).
4. AirDrop or share it to Trace, then **Import**, or **Paste from clipboard**.

## 4. LocalDevVPN

Install [LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044) and connect it (default tunnel address `10.7.0.1`).

## 5. Move

On Wi‑Fi: tap the map or search a place, then **Move**. The joystick, routes and GPX work from there, and the session keeps going on cellular.
