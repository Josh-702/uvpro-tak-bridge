# Testing

## On this repository

```sh
swift test
```

That runs the Swift package. It does not compile the iOS app. iOS needs Xcode, which the cloud Mac runners install. See [RELEASE-NO-MAC.md](RELEASE-NO-MAC.md).

Android, once the Gradle wrapper is present:

```sh
cd android
./gradlew test assembleDebug
```

The package tests include a captured KISS frame for `N0CALL>APRS:!4903.50N/07201.75W-Test`, the public Mic-E destination `S32U6T` (33°25.64'N, Returning, west, no longitude offset), the WB4APR Mic-E longitude bytes `abc` with the +100° offset (169°10.71'W), and course/speed bytes `123` (course 223, speed 212 under the APRS 1.0.1 formula). They also cover message ack text, compressed positions, CoT XML split across reads, protobuf framing that must not desync XML, Part 97 refusals, SmartBeaconing, zip inflate, a data package that contains only `127.0.0.1:17747`, offline queue then online flush, and uid dedupe.

`swift test` was run here on Linux with Swift 6.2.3. The iOS target was not compiled here. There is no Xcode on this machine.

## M0 spike: will iTAK stay attached?

Do this on a real iPhone. The simulator has no Bluetooth radio, and background behavior is not the same.

1. Install a build from TestFlight. Install iTAK from the App Store.
2. On the UV-PRO (firmware 0.7.11 or newer): Menu, General Settings, KISS TNC, On. Quit the BTECH app, or whichever app last used the radio.
3. In Open UV Bridge, connect to the radio. Set your callsign only if you intend to transmit.
4. Tap Add to iTAK and import the zip. Confirm iTAK shows one server, `127.0.0.1:17747` TCP, and that it connects.
5. Hear or inject a station. Confirm one pin.
6. Send both apps to the background. Wait five minutes. Open iTAK and see whether the server is still connected and whether a new RF station still appears. Write down the result.
7. If iTAK drops the TCP server, or refuses the package, switch the bridge's local endpoint to TLS, share a new package, import it once, and repeat step 6. Write down which transport stays up.
8. Turn on airplane mode. Confirm iTAK still shows the same server entry, the pins you already had, and that a GeoChat to an APRS callsign is queued or sent on RF with no cell service. Confirm you were not asked to edit the server.
9. Configure an upstream TAK server and turn airplane mode off. Confirm iTAK's server list did not change, the RF station appears once on the upstream server, and a station seen on both paths is still one pin.
10. Turn airplane mode on again, generate another RF position, then turn it off. Confirm the queued position shows up on the upstream server after the bridge reconnects, and that it was not sent twice.

Record the iTAK version, the phone model, and the iOS version next to the TCP and TLS results.

## TestFlight checklist

The build itself is produced in the cloud. [RELEASE-NO-MAC.md](RELEASE-NO-MAC.md) is the click path. Before you invite testers:

- The bundle id is `net.wa7brm.openuvbridge`.
- Export compliance is already set: the app uses no non-exempt encryption. The radio path is cleartext. TLS is the standard stack.
- Privacy strings cover Bluetooth, location, and the local network.
- Background modes are `bluetooth-central` and `location`. In the review notes, say the app must stay connected to a Bluetooth TNC and beacon the operator's position.
- The data package contains no upstream host, no certificate, and no password.
- Your callsign is not the default. The field ships blank.
- On a device: connect a radio, import the package into iTAK, confirm one server, send one GeoChat, and read the TX log.
- Add internal testers in App Store Connect after the build finishes processing.
- Do not upload a provisioning profile, a `.p8` key, or a `.p12` into the git repository.
