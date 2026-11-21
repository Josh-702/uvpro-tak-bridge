# Contributing

Open UV Bridge is licensed Apache-2.0. Copyright 2026 Josh Howard (WA7BRM).

## Developer Certificate of Origin

Every commit must include a `Signed-off-by` line. That line is the
[Developer Certificate of Origin](https://developercertificate.org/), version 1.1.
By adding it, you certify that you can submit the change under the Apache-2.0 license.

```
Signed-off-by: Your Name <you@example.com>
```

`git commit -s` adds the line for you.

## What belongs on the air

Do not add encryption, obfuscation, or a cipher to anything that can be sent to the radio. Part 97 does not allow it, and `UVBridgeCore.radioEncryptionAvailable` stays false. TLS to a TAK server is internet traffic, not an emission.

Do not commit callsigns as a default transmit identity, server addresses, certificates, passwords, API keys, or provisioning profiles. Tests use `example.test` and obvious placeholders such as `test-password`.

## Checks

```sh
swift test
```

The iOS app is generated with XcodeGen from `project.yml`. The Android app is `cd android && ./gradlew test assembleDebug`.

Do not copy code from Meshtastic-Apple (GPL-3.0) or from atakmaps/TAK-UV-CORE (Commons Clause). Read those projects for ideas only.
