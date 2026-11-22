# Open UV Bridge

[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](https://github.com/Josh-702/uvpro-tak-bridge/blob/main/LICENSE)

Open UV Bridge is a free bridge between a Bluetooth KISS handheld and iTAK. iTAK cannot load plugins, so the app hosts a small TAK server on the phone. You import one data package. That server entry stays put when you have cell service and when you do not.

It is an open alternative to a closed Android-only radio relay. It is not affiliated with TAK, iTAK, or BTECH. The working name does not lead with those marks.

Josh Howard, WA7BRM (General), Las Vegas, Nevada. Licensed under [Apache-2.0](https://github.com/Josh-702/uvpro-tak-bridge/blob/main/LICENSE).

## What it does

- Connects to a UV-PRO (firmware 0.7.11 or newer) over the open BLE KISS service. The same bytes cover Mobilinkd, PicoAPRS, the Vero VR-N76, and the Radioddity GA-5WB. Android also falls back to Bluetooth Classic SPP KISS, which an iPhone cannot use. The on-air format is the same either way. See [docs/ON-AIR-FORMAT.md](docs/ON-AIR-FORMAT.md).
- Turns APRS positions, objects, items, status, and messages into CoT for iTAK, and turns your GeoChat into APRS messages.
- Keeps iTAK on `127.0.0.1:17747` only. Offline, APRS is radio to radio and iTAK still has a map and chat. Online, the app also bridges to the TAK server you configure, queues while it is unreachable, and dedupes stations that show up on both paths.
- Will not transmit until you set a callsign. Your callsign goes out in the clear on every transmission. The default mode is team only: no APRS-IS, an empty digipeater path, and RF stations that are not on the team roster are dropped. Public APRS, with `WIDE1-1,WIDE2-1`, is available and off. Emergency encryption of the payload is off until you accept the Part 97 warning. WA7BRM-7 is an example, not a default.
- On a UV-PRO the same Bluetooth link can run KISS and the radio's control service, so the app can show channel, volume, power, and battery, and offer next/previous channel from a notification.

## Radio setup

1. Update the handheld to firmware 0.7.11 or newer.
2. Menu, General Settings, KISS TNC, On.
3. Quit the vendor app. The radio keeps a single Bluetooth link. If it is busy, the bridge says so.
4. Install this app and iTAK.
5. Connect to the radio.
6. Tap **Add to iTAK** and import the zip. Do this once. Do not point iTAK at your upstream server. The bridge does that when the phone can reach it.
7. When you are ready to transmit, set your own callsign and SSID.

## Build

Swift package, on Linux or a Mac:

```sh
swift test
```

iOS app (needs Xcode, or the cloud Mac in [docs/RELEASE-NO-MAC.md](docs/RELEASE-NO-MAC.md)):

```sh
brew install xcodegen
xcodegen generate
open OpenUVBridge.xcodeproj
```

The generated project is not committed. Android:

```sh
cd android
./gradlew test assembleDebug
```

There is no Xcode on the machine where this tree was first tested. `swift test` passed there with Swift 6.2.3. The iOS target is source-complete and is compiled by the macOS CI job with signing turned off until you add the TestFlight secrets. The Android debug APK is built by `.github/workflows/android.yml`.

## Docs

- [Architecture](docs/ARCHITECTURE.md)
- [Testing, the iTAK background spike, and the TestFlight checklist](docs/TESTING.md)
- [Releasing without a Mac](docs/RELEASE-NO-MAC.md)
- [Contributing and the DCO](CONTRIBUTING.md)

## References

Protocol behavior follows the public specs, not copied code.

- BLE KISS: [hessu/aprs-specs BLE-KISS-API.md](https://github.com/hessu/aprs-specs/blob/master/BLE-KISS-API.md)
- Why a local server instead of a plugin: [Meshtastic, No Plugins, No Problem](https://meshtastic.org/blog/tak-server-integration-ios/) (ideas only; their iOS app is GPL-3.0)
- APRS 1.0.1 and [WB4APR's Mic-E examples](https://www.aprs.org/aprs12/mic-e-examples.txt)
- Part 97, including 47 CFR 97.113 on encryption and identification

Apache-2.0 and MIT projects that were useful as references, and were not copied: khusmann/benlink, Ylianst/HTCommander, flighttactics/SwiftTAK, snstac/aprscot, darksteal/BTECH-Relay. atakmaps/TAK-UV-CORE is Commons Clause and was not used.
