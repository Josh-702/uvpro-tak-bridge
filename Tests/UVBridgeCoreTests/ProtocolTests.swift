// Copyright 2026 Josh Howard
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import UVBridgeCore

final class ProtocolTests: XCTestCase {
    func testBLEKISSUUIDsMatchTheOpenSpec() {
        XCTAssertEqual(BLEKISS.serviceUUID, "00000001-BA2A-46C9-AE49-01B0961F68BB")
        XCTAssertEqual(BLEKISS.transmitCharacteristicUUID, "00000002-BA2A-46C9-AE49-01B0961F68BB")
        XCTAssertEqual(BLEKISS.receiveCharacteristicUUID, "00000003-BA2A-46C9-AE49-01B0961F68BB")
    }

    func testCapturedUncompressedPositionFrame() {
        // KISS-wrapped UI frame for N0CALL>APRS:!4903.50N/07201.75W-Test
        // Latitude and longitude are the classic APRS 1.0.1 position example.
        let hex = "c00082a0a4a64040609c60868298986103f021343930332e35304e2f30373230312e3735572d54657374c0"
        let frames = KISSStreamDecoder().append(Hex.decode(hex)!)
        XCTAssertEqual(frames.count, 1)
        let ax = AX25Frame.decode(frames[0].payload)
        XCTAssertEqual(ax?.source.display, "N0CALL")
        XCTAssertEqual(ax?.destination.display, "APRS")
        let packet = APRS.parseHeard(frame: ax!)
        guard case .position(let position) = packet.body else {
            return XCTFail("expected a position")
        }
        XCTAssertEqual(position.latitude, 49.0 + 3.50 / 60.0, accuracy: 0.00001)
        XCTAssertEqual(position.longitude, -(72.0 + 1.75 / 60.0), accuracy: 0.00001)
        XCTAssertEqual(position.symbolTable, "/")
        XCTAssertEqual(position.symbol, "-")
        XCTAssertEqual(position.comment, "Test")
    }

    func testKISSEscapingAndSplitNotifications() {
        var payload = Data([0x00, 0xC0, 0xDB, 0x11])
        payload.append(contentsOf: Data(repeating: 0x20, count: 20))
        let encoded = KISS.encode(KISSFrame(payload: payload))
        XCTAssertTrue(encoded.contains(0xDB))
        let decoder = KISSStreamDecoder()
        XCTAssertTrue(decoder.append(encoded.prefix(3)).isEmpty)
        let frames = decoder.append(encoded.dropFirst(3))
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].payload, payload)
    }

    func testAX25DigipeaterRoundTrip() {
        let frame = AX25Frame(
            destination: AX25Address(call: "APRS"),
            source: AX25Address(call: "WA7BRM", ssid: 7),
            digipeaters: [
                AX25Address(call: "WIDE1", ssid: 1),
                AX25Address(call: "WIDE2", ssid: 1, repeated: true),
            ],
            info: Data("=3609.55N/11508.39W[Las Vegas".utf8)
        )
        let decoded = AX25Frame.decode(frame.encode()!)
        XCTAssertEqual(decoded?.source.display, "WA7BRM-7")
        XCTAssertEqual(decoded?.digipeaters.map(\.display), ["WIDE1-1", "WIDE2-1"])
        XCTAssertEqual(decoded?.digipeaters.last?.repeated, true)
        XCTAssertTrue(decoded?.monitor.contains("WIDE2-1*") == true)
    }

    func testMessageAckObjectAndStatus() {
        let message = APRSBuilder.message(to: "WA7BRM-7", body: "On the strip", id: "07")
        XCTAssertEqual(message, ":WA7BRM-7 :On the strip{07")
        XCTAssertNil(APRSBuilder.message(to: "WA7BRM-7", body: String(repeating: "A", count: 68), id: "01"))
        let parsed = parseInfo(message!)
        guard case .message(let body) = parsed else { return XCTFail() }
        guard case .text(let text, let id) = body.kind else { return XCTFail() }
        XCTAssertEqual(body.addressee, "WA7BRM-7")
        XCTAssertEqual(text, "On the strip")
        XCTAssertEqual(id, "07")
        let ack = parseInfo(APRSBuilder.ack(to: "N0CALL", id: "07")!)
        guard case .message(let ackBody) = ack, case .ack(let ackID) = ackBody.kind else { return XCTFail() }
        XCTAssertEqual(ackID, "07")
        let object = APRSBuilder.object(name: "UVBRIDGE", latitude: 36 + 9.55 / 60.0, longitude: -(115 + 8.39 / 60.0), comment: "Las Vegas", timestamp: Date(timeIntervalSince1970: 0))
        guard case .object(let report) = parseInfo(object!) else { return XCTFail("\(object ?? "")") }
        XCTAssertEqual(report.name, "UVBRIDGE")
        XCTAssertEqual(report.position.latitude, 36 + 9.55 / 60.0, accuracy: 0.0002)
        XCTAssertEqual(report.position.comment, "Las Vegas")
        guard case .status(let status) = parseInfo(">On watch at the strip") else { return XCTFail() }
        XCTAssertEqual(status.text, "On watch at the strip")
    }

    func testCompressedRoundTripAndCourseSpeed() {
        let text = APRSBuilder.compressedPosition(
            latitude: 36.1699,
            longitude: -115.1398,
            symbolTable: ">",
            symbol: "j",
            comment: "LV",
            courseDegrees: 90,
            speedKnots: 40
        )
        guard case .position(let position) = parseInfo(text!) else { return XCTFail(text ?? "") }
        XCTAssertEqual(position.latitude, 36.1699, accuracy: 0.001)
        XCTAssertEqual(position.longitude, -115.1398, accuracy: 0.001)
        XCTAssertEqual(position.courseDegrees ?? -1, 90, accuracy: 2)
        XCTAssertEqual(position.speedKnots ?? -1, 40, accuracy: 5)
        XCTAssertTrue(position.compressed)
    }

    func testMicEDestinationAndWB4APRLongitudeBytes() {
        // Worked public example: destination S32U6T is 33°25.64'N, standard
        // message bits 1/0/0 (Returning), longitude offset +0, west.
        let header = MicE.decodeDestination("S32U6T")
        XCTAssertEqual(header?.latitude ?? 0, 33.0 + 25.64 / 60.0, accuracy: 0.00001)
        XCTAssertEqual(header?.bits, [true, false, false])
        XCTAssertEqual(header?.message, "Returning")
        XCTAssertEqual(header?.longitudeOffset100, false)
        XCTAssertEqual(header?.west, true)
        XCTAssertNil(MicE.encode(latitude: 36, longitude: -115, bits: [false, false, false], custom: false))

        // aprs.org mic-e-examples.txt uses info bytes abc123. With the +100
        // offset those are 169°10.71' and, by the APRS 1.0.1 course/speed
        // formula, course 223 speed 212. The examples file's "014" does not
        // match that formula for these same bytes; course 223 does.
        let longitude = MicE.decodeLongitude(degrees: UInt8(ascii: "a"), minutes: UInt8(ascii: "b"), hundredths: UInt8(ascii: "c"), offset100: true, west: true)
        XCTAssertEqual(longitude ?? 0, -(169.0 + 10.71 / 60.0), accuracy: 0.00001)
        let motion = MicE.decodeCourseSpeed(sp: UInt8(ascii: "1"), dc: UInt8(ascii: "2"), se: UInt8(ascii: "3"))
        XCTAssertEqual(motion.course, 223, accuracy: 0.01)
        XCTAssertEqual(motion.speed, 212, accuracy: 0.01)

        let encoded = MicE.encode(latitude: 36.17, longitude: -115.14, symbol: ">", courseDegrees: 223, speedKnots: 212)
        let parsed = MicE.parse(info: [UInt8](encoded!.info), destination: AX25Address(call: encoded!.destination))
        XCTAssertEqual(parsed?.latitude ?? 0, 36.17, accuracy: 0.01)
        XCTAssertEqual(parsed?.longitude ?? 0, -115.14, accuracy: 0.02)
        XCTAssertEqual(parsed?.courseDegrees ?? 0, 223, accuracy: 0.01)
        XCTAssertEqual(parsed?.speedKnots ?? 0, 212, accuracy: 0.01)
        XCTAssertEqual(parsed?.symbol, ">")
    }

    func testCoTRoundTripSymbolAndChat() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var position = APRSPosition(latitude: 36.1699, longitude: -115.1398, symbolTable: "/", symbol: ">", comment: "Las Vegas & <strip>")
        position.courseDegrees = 180
        position.speedKnots = 10
        let event = APRSCOT.positionEvent(
            position: position,
            callsign: "N0CALL-1",
            uid: "APRS-N0CALL-1",
            now: now,
            staleAfter: 1800,
            origin: "rf",
            sources: "rf",
            txid: "rf-1"
        )
        XCTAssertEqual(event.type, "a-f-G-E-V-C")
        XCTAssertEqual(SymbolMap.cotType(symbolTable: "/", symbol: "["), "a-f-G-U-C-I")
        let parsed = COTXML.parseEvents(in: event.xml)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].uid, "APRS-N0CALL-1")
        XCTAssertEqual(parsed[0].callsign, "N0CALL-1")
        XCTAssertEqual(parsed[0].remarks, "Las Vegas & <strip>")
        XCTAssertEqual(parsed[0].latitude, 36.1699, accuracy: 0.000001)
        XCTAssertEqual(parsed[0].bridge?.txid, "rf-1")
        XCTAssertEqual(parsed[0].speedMetersPerSecond ?? 0, 10 * 1852.0 / 3600.0, accuracy: 0.01)

        let chat = APRSCOT.chatEvent(from: "N0CALL", fromUID: "APRS-N0CALL", to: "WA7BRM-7", toUID: "APRS-WA7BRM-7", text: "hello", messageID: "07", latitude: 36, longitude: -115, now: now, staleAfter: 3600)
        let route = GeoChat.route(COTXML.parseEvents(in: chat.xml)[0])
        XCTAssertEqual(route?.senderCallsign, "N0CALL")
        XCTAssertEqual(route?.recipientCallsign, "WA7BRM-7")
        XCTAssertEqual(route?.text, "hello")
        XCTAssertEqual(COTXML.parseEvents(in: "not xml").count, 0)
    }

    func testStreamReassemblyAndProtobufSkip() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let event = COTEvent(uid: "APRS-N0CALL", type: "a-f-G-U-C", time: now, stale: now.addingTimeInterval(60), how: "m-g", latitude: 1, longitude: 2, callsign: "N0CALL")
        let xml = event.xml
        let stream = COTByteStream()
        let split = xml.index(xml.startIndex, offsetBy: 12)
        XCTAssertTrue(stream.append(Data(xml[..<split].utf8)).isEmpty)
        let got = stream.append(Data(xml[split...].utf8))
        XCTAssertEqual(got.count, 1)
        var mixed = Data([0xBF, 0x02, 0x11, 0x22])
        mixed.append(contentsOf: Data(xml.utf8))
        let both = COTByteStream().append(mixed)
        XCTAssertEqual(both.count, 2)
    }

    func testPart97AndSmartBeacon() {
        XCTAssertFalse(UVBridgeCore.radioEncryptionAvailable)
        let policy = Part97Policy()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(Part97Guard.evaluate(TXCandidate(callsign: "", infoBytes: 10, now: now), policy: policy), .refuse(.callsignNotSet))
        XCTAssertEqual(
            Part97Guard.evaluate(TXCandidate(callsign: "WA7BRM", payloadIsEncrypted: true, infoBytes: 10, now: now), policy: policy),
            .refuse(.encryptionNotAllowed)
        )
        XCTAssertEqual(
            Part97Guard.evaluate(TXCandidate(callsign: "WA7BRM", isThirdParty: true, isOperatorTraffic: false, infoBytes: 10, now: now), policy: policy),
            .refuse(.thirdParty)
        )
        XCTAssertEqual(
            Part97Guard.evaluate(TXCandidate(callsign: "WA7BRM", messageCharacters: 68, infoBytes: 80, now: now), policy: policy),
            .refuse(.messageTooLong)
        )
        if case .delay(let wait) = Part97Guard.evaluate(
            TXCandidate(callsign: "WA7BRM", infoBytes: 10, recentTransmissions: [now], now: now.addingTimeInterval(1)),
            policy: policy
        ) {
            XCTAssertEqual(wait, 7, accuracy: 0.01)
        } else {
            XCTFail("expected a delay")
        }
        let beacon = SmartBeaconConfig()
        XCTAssertEqual(beacon.interval(speedKnots: 0), 1200, accuracy: 0.1)
        XCTAssertEqual(beacon.interval(speedKnots: 60), 60, accuracy: 0.1)
        XCTAssertEqual(beacon.turnThreshold(speedKnots: 60), 34, accuracy: 0.01)
        let corner = SmartBeacon.decide(config: beacon, now: now, lastBeacon: now.addingTimeInterval(-31), speedKnots: 60, courseDegrees: 90, lastCourseDegrees: 0)
        XCTAssertEqual(corner.reason, "corner")
        let held = SmartBeacon.decide(config: beacon, now: now, lastBeacon: now.addingTimeInterval(-10), speedKnots: 60, courseDegrees: 90, lastCourseDegrees: 0)
        XCTAssertFalse(held.shouldBeacon)
        XCTAssertTrue(Callsign.isValidBase("WA7BRM"))
        XCTAssertFalse(Callsign.isValidBase("APRS"))
        XCTAssertEqual(Callsign.parse("wa7brm-7")?.ssid, 7)
    }

    func testZipStoreDeflateAndDataPackageDoesNotEmbedUpstream() throws {
        let plain = Data("hello cot <event uid='x'/>".utf8)
        let inflated = try Inflate.raw(Data(Hex.decode("cb48cdc9c95748ce2f51b0492d4bcd2b5128cd4cb155af50d7b70300")!), expectedSize: plain.count)
        XCTAssertEqual(inflated, plain)

        let archive = ZipArchive.archive(["prefs/cot_streams.pref": Data("127.0.0.1:17747:tcp".utf8)])
        XCTAssertEqual(try ZipArchive.extract(archive)["prefs/cot_streams.pref"], Data("127.0.0.1:17747:tcp".utf8))

        let package = DataPackageBuilder.iTAKPackage()
        let files = try ZipArchive.extract(package)
        let pref = String(data: files["prefs/cot_streams.pref"]!, encoding: .utf8)!
        XCTAssertTrue(pref.contains("127.0.0.1:17747:tcp"))
        XCTAssertFalse(pref.contains("8089"))
        XCTAssertFalse(pref.contains("example.test"))
        XCTAssertTrue(files["readme.txt"] != nil)
        var tls = LocalTAKEndpoint()
        tls.transport = .tls
        let tlsPref = String(data: try ZipArchive.extract(DataPackageBuilder.iTAKPackage(endpoint: tls))["prefs/cot_streams.pref"]!, encoding: .utf8)!
        XCTAssertTrue(tlsPref.contains("127.0.0.1:17747:ssl"))
    }

    func testEnrollmentURLAndImportedPackageRedactsPassword() throws {
        let url = TAKEnrollment.signClientV2URL(host: "example.test", clientUID: "unit")
        XCTAssertEqual(url?.host, "example.test")
        XCTAssertEqual(url?.path, "/Marti/api/tls/signClient/v2")
        XCTAssertNil(TAKEnrollment.signClientV2URL(host: "user:pass@example.test", clientUID: "unit"))
        XCTAssertNil(TAKEnrollment.signClientV2URL(host: "", clientUID: "unit"))
        let body = TAKEnrollment.csrWireBody(pem: "-----BEGIN CERTIFICATE REQUEST-----\nQUJD\n-----END CERTIFICATE REQUEST-----\n")
        XCTAssertEqual(String(data: body!, encoding: .utf8), "QUJD")

        let pref = """
        <preferences><preference name="cot_streams">
        <entry key="connectString0" class="class java.lang.String">example.test:8089:ssl</entry>
        <entry key="caPassword0" class="class java.lang.String">test-password</entry>
        <entry key="caLocation0" class="class java.lang.String">certs/ca.p12</entry>
        </preference></preferences>
        """
        let zip = ZipArchive.archive([
            "prefs/server.pref": Data(pref.utf8),
            "certs/ca.p12": Data([0x01, 0x02, 0x03]),
        ])
        let imported = try TAKPackageImport.load(zip)
        XCTAssertEqual(imported.host, "example.test")
        XCTAssertEqual(imported.port, 8089)
        XCTAssertEqual(imported.transport, .tls)
        XCTAssertEqual(imported.trustStore, Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(imported.trustStorePassword, "test-password")
        XCTAssertFalse(imported.redactedDescription.contains("test-password"))
    }

    private func parseInfo(_ text: String) -> APRSBody {
        let frame = AX25Frame(destination: AX25Address(call: "APRS"), source: AX25Address(call: "N0CALL"), info: Data(text.utf8))
        return APRS.parseHeard(frame: frame).body
    }
}
