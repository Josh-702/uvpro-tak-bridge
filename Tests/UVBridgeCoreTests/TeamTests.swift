// Copyright 2026 Josh Howard
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import UVBridgeCore

final class TeamTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func testTeamDefaultsAndRosterFilter() {
        let config = BridgeConfig()
        XCTAssertEqual(config.operatingMode, .team)
        XCTAssertEqual(config.path, "")
        XCTAssertFalse(config.emergencyEncryption)
        XCTAssertEqual(TeamPolicy.defaultPath(for: .team), "")
        XCTAssertEqual(TeamPolicy.defaultPath(for: .publicAPRS), "WIDE1-1,WIDE2-1")
        XCTAssertFalse(TeamPolicy.allowsBeacon(mode: .team, teamChannelSet: false))
        XCTAssertTrue(TeamPolicy.allowsBeacon(mode: .team, teamChannelSet: true))
        XCTAssertTrue(TeamPolicy.allowsBeacon(mode: .publicAPRS, teamChannelSet: false))
        XCTAssertTrue(TeamPolicy.isNationalAPRSCallingFrequency(megahertz: 144.390))
        XCTAssertFalse(TeamPolicy.isNationalAPRSCallingFrequency(megahertz: 146.520))
        XCTAssertTrue(TeamPolicy.rosterAllows("n0call-7", roster: ["N0CALL"]))
        XCTAssertFalse(TeamPolicy.rosterAllows("W1AW", roster: ["N0CALL"]))

        var team = BridgeConfig()
        team.callsign = "WA7BRM"
        team.ssid = 7
        team.beaconEnabled = false
        team.rosterCallsigns = ["N0CALL"]
        let engine = BridgeEngine(config: team)
        _ = engine.localClientDidConnect(now: t0)
        _ = engine.ingestKISS(kiss("W1AW", "Off team"), now: t0)
        XCTAssertTrue(engine.stations.isEmpty)
        _ = engine.ingestKISS(kiss("N0CALL", "On team"), now: t0)
        XCTAssertEqual(engine.stations.map(\.callsign), ["N0CALL"])
    }

    func testEmergencyFrameKeepsTheCallsignClear() throws {
        let key = TeamKey(bytes: Data(repeating: 7, count: 32))
        let rotated = TeamKey(bytes: Data(repeating: 9, count: 32))
        let plain = Data("!4903.50N/07201.75W-Team".utf8)
        XCTAssertNil(EmergencyFrame.seal(plaintext: plain, key: key, mode: .publicAPRS, enabled: true))
        XCTAssertNil(EmergencyFrame.seal(plaintext: plain, key: key, mode: .team, enabled: false))
        let sealed = try XCTUnwrap(EmergencyFrame.seal(plaintext: plain, key: key, mode: .team, enabled: true))
        XCTAssertTrue(EmergencyFrame.isSealed(sealed))
        XCTAssertEqual(EmergencyFrame.open(sealed: sealed, keys: [key]), plain)
        XCTAssertNil(EmergencyFrame.open(sealed: sealed, keys: [rotated]))
        XCTAssertEqual(EmergencyFrame.open(sealed: sealed, keys: [rotated, key]), plain)
        XCTAssertEqual(TeamKey.parseShareText(key.shareText)?.id, key.id)

        var config = BridgeConfig()
        config.callsign = "WA7BRM"
        config.ssid = 7
        config.beaconEnabled = false
        config.operatingMode = .team
        config.emergencyEncryption = true
        config.rosterCallsigns = ["N0CALL"]
        let engine = BridgeEngine(config: config)
        engine.emergencyKeys = [key]
        _ = engine.radioDidConnect(now: t0)
        let sent = engine.ingestLocalXML(chat("WA7BRM", "N0CALL", "on team"), now: t0)
        let ax = try XCTUnwrap(AX25Frame.decode(KISSStreamDecoder().append(sent.radioFrames[0])[0].payload))
        XCTAssertEqual(ax.source.display, "WA7BRM-7")
        XCTAssertTrue(EmergencyFrame.isSealed(ax.info))
        XCTAssertNotEqual(ax.info, Data("on team".utf8))

        let heard = engine.ingestKISS(kissFrame(source: "N0CALL", info: sealed), now: t0.addingTimeInterval(10))
        XCTAssertFalse(heard.localXML.isEmpty)
        let stranger = engine.ingestKISS(kissFrame(source: "W1AW", info: sealed), now: t0.addingTimeInterval(20))
        XCTAssertTrue(stranger.localXML.isEmpty)
    }

    func testBenshiChannelPowerAndSelectedMemory() {
        let request = BenshiRadio.readChannelRequest(3)
        let decoded = BenshiMessage(bytes: request.bytes)
        XCTAssertEqual(decoded?.command, BenshiCommand.readChannel)
        XCTAssertEqual(decoded?.isReply, false)

        var body = Data(repeating: 0, count: 25)
        body[0] = 3
        // Receive frequency sits after 8+2+30+2 = 42 bits. 146.520 MHz is 146_520_000 Hz.
        body = BenshiRadio.setPower(.high, inChannelBody: body) ?? body
        let selected = BenshiRadio.settingSelectedChannel(0x2A, in: Data(repeating: 0, count: 16))
        XCTAssertEqual(BenshiRadio.selectedChannel(in: selected!), 0x2A)
        let patched = BenshiRadio.setPower(.medium, inChannelBody: body)
        XCTAssertEqual(BenshiRadio.channel(fromBody: patched!)?.power, .medium)
        XCTAssertTrue(OperatorHint.emergencyEncryptionWarning.contains("97.113"))
        XCTAssertTrue(OperatorHint.emergencyEncryptionWarning.contains("97.403"))
        XCTAssertTrue(OperatorHint.part97Clear.contains("callsign"))
    }

    private func kiss(_ source: String, _ comment: String) -> Data {
        kissFrame(source: source, info: Data(APRSBuilder.uncompressedPosition(latitude: 36, longitude: -115, comment: comment)!.utf8))
    }

    private func kissFrame(source: String, info: Data) -> Data {
        let frame = AX25Frame(
            destination: AX25Address(call: "APRS"),
            source: AX25Address(call: source),
            info: info
        )
        return KISS.encode(KISSFrame(payload: frame.encode()!))
    }

    private func chat(_ from: String, _ to: String, _ text: String) -> String {
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
            chat: COTChat(roomID: to, room: to, senderCallsign: from, senderUID: "iTAK-\(from)", recipientUID: to)
        ).xml
    }
}
