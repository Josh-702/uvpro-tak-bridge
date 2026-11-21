# On-air format

An iPhone and an Android phone running Open UV Bridge have to hear each other. They do that by putting the same bytes on the air and the same CoT in ATAK and iTAK. The contract is `testdata/on-air-vectors.json`. The Swift tests and the Kotlin tests both load that file and fail if a builder, a parser, a uid, or a CoT document drifts.

## What goes on the radio

AX.25 UI frames inside KISS. The command byte is `0x00`. `0xC0` and `0xDB` inside the frame are escaped the usual way. Control is `0x03`, PID is `0xF0`. Addresses are shifted ASCII, SSID in the high nibble of the last byte, with the extension bit set on the final address.

A position from this app is an uncompressed APRS report, messaging capable, so it starts with `=`:

```
=3610.19N/11508.39W[LV
```

Latitude is `DDMM.mm` plus `N` or `S`. Longitude is `DDDMM.mm` plus `E` or `W`. The symbol table and symbol are the two characters around the longitude. The default symbol is `/[` (a person). The comment is plain ASCII. Course and speed, when present, are `DDD/DDD` immediately after the symbol.

The destination call is `APRS`. The source is the operator's callsign and SSID. The default path is `WIDE1-1,WIDE2-1`. The shared vector's transmit frame is the KISS hex for `WA7BRM-7>APRS,WIDE1-1,WIDE2-1:=3610.19N/11508.39W[LV`. That callsign is an example in the test file, not a default. The settings field ships blank, and the Part 97 guard refuses to transmit until a real callsign is set.

A direct message is the standard 67-character APRS message. The addressee is padded to 9 characters:

```
:WA7BRM-7 :On the strip{07
```

An ack is `:N0CALL   :ack07`. An object is the 9-character name form:

```
;UVBRIDGE *010000z3609.55N/11508.39W-Las Vegas
```

Mic-E is decoded, not used for the default beacon, so a Kenwood or a UV-PRO tracker still shows up. Destination `S32U6T` is 33°25.64'N, standard message Returning, west, longitude offset +0. That is the worked public example both suites lock.

Android may carry those same KISS bytes over BLE or over Bluetooth Classic SPP (`00001101-0000-1000-8000-00805F9B34FB`). iOS can only use BLE. The bytes after the radio do not change.

## What ATAK and iTAK see

A station uid is `APRS-` plus the callsign, with `-<ssid>` only when the SSID is not zero. `WA7BRM` with SSID 7 is `APRS-WA7BRM-7`. An object is `APRS-OBJ-` plus the name. A GeoChat uid is `GeoChat.<from-uid>.<to-uid>.<message id>`, so `GeoChat.APRS-WA7BRM-7.APRS-N0CALL.07` is the same chat on both phones.

Symbol to CoT type, same table on both platforms:

| APRS symbol | CoT type |
| --- | --- |
| `[` person, `b` bike | `a-f-G-U-C-I` |
| `>` car, `k` truck, `j` jeep, `v` van, `<` motorcycle | `a-f-G-E-V-C` |
| `-` house, `r` repeater | `a-f-G-I` |
| anything else | `a-f-G-U-C` |

The captured frame `N0CALL>APRS:!4903.50N/07201.75W-Test` is the APRS 1.0.1 position. Both apps emit this CoT, timestamps included, for `2023-11-14T22:13:20.000Z`:

```xml
<event version="2.0" uid="APRS-N0CALL" type="a-f-G-I" ...>
  <point lat="49.058333" lon="-72.029167" hae="9999999.0" .../>
  <contact callsign="N0CALL"/>
  <remarks>Test</remarks>
</event>
```

The full document, including the `<uvbridge txid="rf-shared-1">` tag, is in the vector file. Positions go stale 30 minutes later. A chat from `WA7BRM-7` to `N0CALL` is type `b-t-f`, how `h-g-i-g-o`, and the text is the remarks.

A station heard on RF and again from a TAK server keeps that one uid. The map does not grow a second pin.

## What must not change without both suites

If you change a pad width, a uid, a symbol type, or the CoT attribute order, update `testdata/on-air-vectors.json` and make `swift test` and `cd android && ./gradlew test` pass together. A change that only one language knows about will split a mixed team.
