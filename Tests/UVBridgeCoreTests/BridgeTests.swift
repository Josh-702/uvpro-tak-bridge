// Copyright 2026 Josh Howard
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import UVBridgeCore

final class BridgeTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func testOfflineQueuesUpstreamAndOnlineFlushesOnce() {
        let engine = makeEngine(callsign: "WA7BRM", ssid: 7, beacon: false)
        XCTAssertEqual(engine.setPath(satisfied: false, now: t0).upstreamXML.count, 0)
        XCTAssertEqual(engine.mode, .offline)
        XCTAssertTrue(engine.mode.summary.contains("iTAK"))
        XCTAssertTrue(engine.mode.keepsSingleITAKServer)
        let heard = engine.ingestKISS(kiss(source: "N0CALL", info: position(36.17, -115.14, "Strip")), now: t0)
        XCTAssertTrue(heard.localXML.isEmpty)
        XCTAssertEqual(engine.pendingLocal, 1)
        XCTAssertEqual(engine.pendingUpstream, 1)
        XCTAssertTrue(heard.upstreamXML.isEmpty)
        let connected = engine.localClientDidConnect(now: t0)
        XCTAssertEqual(connected.localXML.count, 1)
        XCTAssertTrue(connected.localXML[0].contains("APRS-N0CALL"))
        XCTAssertEqual(engine.localEndpoint.connectString, "127.0.0.1:17747:tcp")

        _ = engine.setPath(satisfied: true, now: t0)
        XCTAssertEqual(engine.mode, .serverUnreachable)
        XCTAssertTrue(engine.wantsUpstreamSocket)
        let bridged = engine.noteUpstreamReady(now: t0)
        XCTAssertEqual(bridged.upstreamXML.count, 1)
        XCTAssertEqual(engine.pendingUpstream, 0)
        XCTAssertEqual(engine.mode, .bridging)
        XCTAssertTrue(engine.mode.summary.contains("on-phone server"))
        XCTAssertTrue(engine.noteUpstreamReady(now: t0).upstreamXML.isEmpty)
        XCTAssertEqual(engine.localEndpoint.connectString, "127.0.0.1:17747:tcp")

        _ = engine.setPath(satisfied: false, now: t0.addingTimeInterval(30))
        XCTAssertEqual(engine.mode, .offline)
        _ = engine.ingestKISS(kiss(source: "K7ABC", info: position(36.2, -115.2, "East")), now: t0.addingTimeInterval(30))
        XCTAssertEqual(engine.pendingUpstream, 1)
        XCTAssertEqual(engine.stations.count, 2)
        _ = engine.setPath(satisfied: true, now: t0.addingTimeInterval(40))
        let again = engine.noteUpstreamReady(now: t0.addingTimeInterval(40))
        XCTAssertEqual(again.upstreamXML.count, 1)
        XCTAssertTrue(again.upstreamXML[0].contains("APRS-K7ABC"))
    }

    func testStationsDoNotDoubleWhenSeenOnRFAndServer() {
        let engine = makeEngine(callsign: "WA7BRM", ssid: 7, beacon: false)
        _ = engine.localClientDidConnect(now: t0)
        _ = engine.setPath(satisfied: true, now: t0)
        let first = engine.ingestKISS(kiss(source: "N0CALL", info: position(36.10, -115.10, "RF")), now: t0)
        _ = engine.noteUpstreamReady(now: t0)
        let echo = engine.ingestUpstreamBytes(Data(first.localXML[0].utf8), now: t0.addingTimeInterval(1))
        XCTAssertTrue(echo.localXML.isEmpty)
        XCTAssertEqual(engine.stations.count, 1)
        XCTAssertEqual(engine.stations[0].sources, [.rf, .server])

        let moved = COTEvent(
            uid: "APRS-N0CALL",
            type: "a-f-G-U-C",
            time: t0.addingTimeInterval(20),
            stale: t0.addingTimeInterval(1800),
            how: "m-g",
            latitude: 36.5,
            longitude: -115.5,
            callsign: "N0CALL",
            remarks: "from server"
        )
        let update = engine.ingestUpstreamBytes(Data(moved.xml.utf8), now: t0.addingTimeInterval(20))
        XCTAssertEqual(engine.stations.count, 1)
        XCTAssertEqual(engine.stations[0].latitude ?? 0, 36.5, accuracy: 0.0001)
        XCTAssertEqual(update.localXML.count, 1)
        XCTAssertEqual(engine.picture(now: t0).count, 1)
        XCTAssertEqual(engine.picture(now: t0)[0].uid, "APRS-N0CALL")
    }

    func testServerOnlyStationsStayOffTheMapUnlessMirrored() {
        let engine = makeEngine(callsign: "WA7BRM", ssid: 7, beacon: false)
        _ = engine.localClientDidConnect(now: t0)
        let stranger = COTEvent(uid: "APRS-W1AW", type: "a-f-G-U-C", time: t0, stale: t0.addingTimeInterval(60), how: "m-g", latitude: 41.7, longitude: -72.7, callsign: "W1AW")
        let hidden = engine.ingestUpstreamBytes(Data(stranger.xml.utf8), now: t0)
        XCTAssertTrue(hidden.localXML.isEmpty)
        XCTAssertTrue(engine.stations.isEmpty)
        engine.config.mirrorAllServerStations = true
        let shown = engine.ingestUpstreamBytes(Data(stranger.xml.utf8), now: t0)
        XCTAssertEqual(shown.localXML.count, 1)
        XCTAssertEqual(engine.stations.count, 1)
    }

    func testOperatorGeoChatGoesToRFAndAllChatDoesNot() throws {
        let engine = makeEngine(callsign: "WA7BRM", ssid: 7, beacon: false)
        _ = engine.radioDidConnect(now: t0)
        _ = engine.localClientDidConnect(now: t0)
        let direct = chat(from: "WA7BRM", to: "N0CALL", room: "N0CALL", text: "On the strip")
        let sent = engine.ingestLocalXML(direct.xml, now: t0)
        XCTAssertEqual(sent.radioFrames.count, 1)
        XCTAssertEqual(engine.txLog.count, 1)
        let ax = AX25Frame.decode(KISSStreamDecoder().append(sent.radioFrames[0])[0].payload)
        let text = String(data: ax!.info, encoding: .utf8)!
        XCTAssertTrue(text.contains(":N0CALL   :On the strip{"))
        XCTAssertEqual(ax?.source.display, "WA7BRM-7")
        XCTAssertTrue(ax?.monitor.contains("WIDE1-1,WIDE2-1") == true)

        let all = chat(from: "WA7BRM", to: "All Chat Rooms", room: "All Chat Rooms", text: "everyone")
        let refused = engine.ingestLocalXML(all.xml, now: t0.addingTimeInterval(1))
        XCTAssertTrue(refused.radioFrames.isEmpty)
        XCTAssertEqual(refused.refusals.first?.reason, .notAddressedToRF)

        let other = chat(from: "K7ABC", to: "N0CALL", room: "N0CALL", text: "relay me")
        let third = engine.ingestLocalXML(other.xml, now: t0.addingTimeInterval(2))
        XCTAssertEqual(third.refusals.first?.reason, .thirdParty)
        XCTAssertTrue(third.radioFrames.isEmpty)
    }

    func testBlankCallsignCannotTransmit() {
        let engine = makeEngine(callsign: "", ssid: 0, beacon: true)
        _ = engine.radioDidConnect(now: t0)
        let fix = engine.updateOwnPosition(PositionFix(latitude: 36.17, longitude: -115.14, timestamp: t0), now: t0)
        XCTAssertEqual(fix.refusals.first?.reason, .callsignNotSet)
        XCTAssertTrue(engine.txLog.isEmpty)
        XCTAssertTrue(fix.radioFrames.isEmpty)
        let direct = chat(from: "WA7BRM", to: "N0CALL", room: "N0CALL", text: "hi")
        let chatEffect = engine.ingestLocalXML(direct.xml, now: t0)
        XCTAssertEqual(chatEffect.refusals.first?.reason, .callsignNotSet)
        XCTAssertTrue(engine.txLog.isEmpty)
    }

    func testMessagesAreRateLimitedRetriedAndAcked() {
        var config = configured(callsign: "WA7BRM", ssid: 7, beacon: false)
        config.part97.minimumGap = 8
        config.part97.retryInterval = 45
        let engine = BridgeEngine(config: config)
        _ = engine.radioDidConnect(now: t0)
        let first = engine.ingestLocalXML(chat(from: "WA7BRM", to: "N0CALL", room: "N0CALL", text: "one").xml, now: t0)
        let second = engine.ingestLocalXML(chat(from: "WA7BRM", to: "N0CALL", room: "N0CALL", text: "two").xml, now: t0.addingTimeInterval(1))
        XCTAssertEqual(first.radioFrames.count, 1)
        XCTAssertTrue(second.radioFrames.isEmpty)
        XCTAssertGreaterThanOrEqual(engine.pendingRadio, 1)
        let later = engine.tick(now: t0.addingTimeInterval(9))
        XCTAssertEqual(later.radioFrames.count, 1)
        let ackInfo = APRSBuilder.ack(to: "WA7BRM-7", id: "00")!
        _ = engine.ingestAX25(AX25Frame(destination: AX25Address(call: "APRS"), source: AX25Address(call: "N0CALL"), info: Data(ackInfo.utf8)), now: t0.addingTimeInterval(20))
        let retry = engine.tick(now: t0.addingTimeInterval(50))
        let monitors = retry.radioFrames.compactMap { frame -> String? in
            AX25Frame.decode(KISSStreamDecoder().append(frame).first?.payload ?? Data()).map { String(data: $0.info, encoding: .utf8) ?? "" }
        }
        XCTAssertFalse(monitors.contains { $0.contains("{00") }, "message 00 was acked: \(monitors)")
    }

    func testIncomingMessageIsAckedAndBeaconsUseSmartBeaconing() {
        let engine = makeEngine(callsign: "WA7BRM", ssid: 7, beacon: true)
        _ = engine.radioDidConnect(now: t0)
        _ = engine.localClientDidConnect(now: t0)
        let info = APRSBuilder.message(to: "WA7BRM-7", body: "copy", id: "03")!
        let heard = engine.ingestAX25(AX25Frame(destination: AX25Address(call: "APRS"), source: AX25Address(call: "N0CALL"), info: Data(info.utf8)), now: t0)
        XCTAssertEqual(heard.radioFrames.count, 1)
        let ackText = String(data: AX25Frame.decode(KISSStreamDecoder().append(heard.radioFrames[0])[0].payload)!.info, encoding: .utf8)!
        XCTAssertTrue(ackText.contains("ack03"))
        XCTAssertEqual(heard.localXML.count, 1)
        let duplicate = engine.ingestAX25(AX25Frame(destination: AX25Address(call: "APRS"), source: AX25Address(call: "N0CALL"), info: Data(info.utf8)), now: t0.addingTimeInterval(1))
        XCTAssertTrue(duplicate.localXML.isEmpty)

        let beacon = engine.updateOwnPosition(PositionFix(latitude: 36.17, longitude: -115.14, courseDegrees: 10, speedKnots: 60, timestamp: t0), now: t0.addingTimeInterval(10))
        XCTAssertEqual(beacon.radioFrames.count, 1)
        let tooSoon = engine.updateOwnPosition(PositionFix(latitude: 36.18, longitude: -115.15, courseDegrees: 12, speedKnots: 60, timestamp: t0), now: t0.addingTimeInterval(15))
        XCTAssertTrue(tooSoon.radioFrames.isEmpty)
    }

    func testOwnStationIsNotPinnedAndSnapshotRoundTrips() throws {
        let engine = makeEngine(callsign: "WA7BRM", ssid: 7, beacon: false)
        _ = engine.ingestKISS(kiss(source: "WA7BRM", ssid: 7, info: position(36, -115, "me")), now: t0)
        XCTAssertTrue(engine.stations.isEmpty)
        _ = engine.ingestKISS(kiss(source: "N0CALL", info: position(36.1, -115.1, "them")), now: t0)
        let data = try JSONEncoder().encode(engine.snapshot())
        let restored = try JSONDecoder().decode(BridgeSnapshot.self, from: data)
        let other = BridgeEngine()
        other.restore(restored)
        XCTAssertEqual(other.stations.count, 1)
        XCTAssertEqual(other.pendingUpstream, 1)
        XCTAssertEqual(other.stations[0].uid, "APRS-N0CALL")
    }

    func testBackoffAndNoUpstreamConfigured() {
        let engine = makeEngine(callsign: "WA7BRM", ssid: 7, beacon: false)
        _ = engine.setPath(satisfied: true, now: t0)
        XCTAssertEqual(engine.mode, .serverUnreachable)
        _ = engine.noteUpstreamFailed(now: t0)
        XCTAssertFalse(engine.wantsUpstreamSocket)
        XCTAssertEqual(engine.nextUpstreamAttempt, t0.addingTimeInterval(1))
        _ = engine.tick(now: t0.addingTimeInterval(1))
        XCTAssertTrue(engine.wantsUpstreamSocket)
        _ = engine.noteUpstreamFailed(now: t0.addingTimeInterval(1))
        XCTAssertEqual(engine.nextUpstreamAttempt, t0.addingTimeInterval(3))

        var localOnly = BridgeConfig()
        localOnly.beaconEnabled = false
        let plain = BridgeEngine(config: localOnly)
        _ = plain.setPath(satisfied: true, now: t0)
        XCTAssertEqual(plain.mode, .onlineLocalOnly)
        _ = plain.ingestKISS(kiss(source: "N0CALL", info: position(1, 2, "x")), now: t0)
        XCTAssertEqual(plain.pendingUpstream, 0)
        XCTAssertTrue(plain.mode.summary.contains("no TAK server"))
    }

    private func makeEngine(callsign: String, ssid: Int, beacon: Bool) -> BridgeEngine {
        BridgeEngine(config: configured(callsign: callsign, ssid: ssid, beacon: beacon))
    }

    private func configured(callsign: String, ssid: Int, beacon: Bool) -> BridgeConfig {
        var config = BridgeConfig()
        config.callsign = callsign
        config.ssid = ssid
        config.beaconEnabled = beacon
        config.upstream = UpstreamConfig(host: "example.test", port: 8089, transport: .tls)
        return config
    }

    private func position(_ lat: Double, _ lon: Double, _ comment: String) -> String {
        APRSBuilder.uncompressedPosition(latitude: lat, longitude: lon, comment: comment)!
    }

    private func kiss(source: String, ssid: Int = 0, info: String) -> Data {
        let frame = AX25Frame(
            destination: AX25Address(call: "APRS"),
            source: AX25Address(call: source, ssid: ssid),
            digipeaters: AX25Frame.digipeaters(fromPath: "WIDE1-1,WIDE2-1")!,
            info: Data(info.utf8)
        )
        return KISS.encode(KISSFrame(payload: frame.encode()!))
    }

    private func chat(from: String, to: String, room: String, text: String) -> COTEvent {
        COTEvent(
            uid: "GeoChat.\(from).\(to).1",
            type: "b-t-f",
            time: t0,
            stale: t0.addingTimeInterval(3600),
            how: "h-g-i-g-o",
            latitude: 36,
            longitude: -115,
            callsign: from,
            remarks: text,
            chat: COTChat(roomID: to, room: room, senderCallsign: from, senderUID: "iTAK-\(from)", recipientUID: to)
        )
    }
}
