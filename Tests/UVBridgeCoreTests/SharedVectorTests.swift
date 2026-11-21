// Copyright 2026 Josh Howard
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import UVBridgeCore

/// The same file is loaded by the Kotlin suite. If this test fails, iPhone and
/// Android would no longer describe the same station or the same chat.
final class SharedVectorTests: XCTestCase {
    func testSharedOnAirVectors() throws {
        let root = try XCTUnwrap(sharedVectorURL())
        let data = try Data(contentsOf: root)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let now = Date(timeIntervalSince1970: json["timeUnix"] as? TimeInterval ?? 0)

        let position = try XCTUnwrap(json["position"] as? [String: Any])
        let kiss = try XCTUnwrap(Hex.decode(position["kissHex"] as? String ?? ""))
        let ax = try XCTUnwrap(AX25Frame.decode(KISSStreamDecoder().append(kiss).first?.payload ?? Data()))
        XCTAssertEqual(ax.source.display, position["source"] as? String)
        XCTAssertEqual(String(data: ax.info, encoding: .utf8), position["info"] as? String)
        guard case .position(let parsed) = APRS.parseHeard(frame: ax).body else {
            return XCTFail("position")
        }
        XCTAssertEqual(parsed.latitude, position["latitude"] as? Double ?? 0, accuracy: 0.0000001)
        XCTAssertEqual(parsed.longitude, position["longitude"] as? Double ?? 0, accuracy: 0.0000001)
        XCTAssertEqual(parsed.symbol, position["symbol"] as? String)
        XCTAssertEqual(parsed.comment, position["comment"] as? String)
        let uid = APRSCOT.stationUID(base: ax.source.call, ssid: ax.source.ssid)
        XCTAssertEqual(uid, position["uid"] as? String)
        let event = APRSCOT.positionEvent(
            position: parsed,
            callsign: ax.source.display,
            uid: uid,
            now: now,
            staleAfter: position["staleSeconds"] as? TimeInterval ?? 0,
            origin: "rf",
            sources: "rf",
            txid: position["txid"] as? String
        )
        XCTAssertEqual(event.type, position["cotType"] as? String)
        XCTAssertEqual(event.xml, position["cotXml"] as? String)

        let message = try XCTUnwrap(json["message"] as? [String: Any])
        XCTAssertEqual(
            APRSBuilder.message(to: message["addressee"] as? String ?? "", body: message["body"] as? String ?? "", id: message["id"] as? String),
            message["info"] as? String
        )
        let ack = try XCTUnwrap(json["ack"] as? [String: Any])
        XCTAssertEqual(APRSBuilder.ack(to: ack["addressee"] as? String ?? "", id: ack["id"] as? String ?? ""), ack["info"] as? String)

        let object = try XCTUnwrap(json["object"] as? [String: Any])
        let objectInfo = APRSBuilder.object(
            name: object["name"] as? String ?? "",
            latitude: (object["latitudeDegrees"] as? Double ?? 0) + (object["latitudeMinutes"] as? Double ?? 0) / 60.0,
            longitude: (object["longitudeDegrees"] as? Double ?? 0) + (object["longitudeMinutes"] as? Double ?? 0) / 60.0,
            comment: object["comment"] as? String ?? "",
            timestamp: Date(timeIntervalSince1970: object["timestampUnix"] as? TimeInterval ?? 0)
        )
        XCTAssertEqual(objectInfo, object["info"] as? String)
        XCTAssertEqual(APRSCOT.objectUID(name: object["name"] as? String ?? "", item: false), object["uid"] as? String)

        let beacon = try XCTUnwrap(json["beacon"] as? [String: Any])
        let beaconInfo = APRSBuilder.uncompressedPosition(
            latitude: beacon["latitude"] as? Double ?? 0,
            longitude: beacon["longitude"] as? Double ?? 0,
            symbolTable: (beacon["symbolTable"] as? String)?.first ?? "/",
            symbol: (beacon["symbol"] as? String)?.first ?? "[",
            comment: beacon["comment"] as? String ?? "",
            messaging: beacon["messaging"] as? Bool ?? true
        )
        XCTAssertEqual(beaconInfo, beacon["info"] as? String)
        let digis = try XCTUnwrap(AX25Frame.digipeaters(fromPath: beacon["path"] as? String ?? ""))
        let frame = AX25Frame(
            destination: AX25Address(call: "APRS"),
            source: AX25Address(call: beacon["source"] as? String ?? "", ssid: beacon["ssid"] as? Int ?? 0),
            digipeaters: digis,
            info: Data((beaconInfo ?? "").utf8)
        )
        XCTAssertEqual(Hex.encode(KISS.encode(KISSFrame(payload: frame.encode()!))), beacon["kissHex"] as? String)

        let chat = try XCTUnwrap(json["chat"] as? [String: Any])
        let chatEvent = APRSCOT.chatEvent(
            from: chat["from"] as? String ?? "",
            fromUID: chat["fromUid"] as? String ?? "",
            to: chat["to"] as? String ?? "",
            toUID: chat["toUid"] as? String ?? "",
            text: chat["text"] as? String ?? "",
            messageID: chat["messageId"] as? String ?? "",
            latitude: chat["latitude"] as? Double ?? 0,
            longitude: chat["longitude"] as? Double ?? 0,
            now: now,
            staleAfter: chat["staleSeconds"] as? TimeInterval ?? 0
        )
        XCTAssertEqual(chatEvent.uid, chat["uid"] as? String)
        XCTAssertEqual(chatEvent.xml, chat["cotXml"] as? String)

        let mice = try XCTUnwrap(json["mice"] as? [String: Any])
        let header = try XCTUnwrap(MicE.decodeDestination(mice["destination"] as? String ?? ""))
        XCTAssertEqual(header.latitude, mice["latitude"] as? Double ?? 0, accuracy: 0.0000001)
        XCTAssertEqual(header.message, mice["message"] as? String)
        XCTAssertEqual(header.west, mice["west"] as? Bool)
        XCTAssertEqual(header.longitudeOffset100, mice["longitudeOffset100"] as? Bool)

        let symbols = try XCTUnwrap(json["symbols"] as? [String: String])
        for (symbol, type) in symbols {
            XCTAssertEqual(SymbolMap.cotType(symbolTable: "/", symbol: symbol), type, symbol)
        }
        let station = try XCTUnwrap(json["stationUid"] as? [String: Any])
        XCTAssertEqual(
            APRSCOT.stationUID(base: station["base"] as? String ?? "", ssid: station["ssid"] as? Int ?? 0),
            station["uid"] as? String
        )
    }

    private func sharedVectorURL() -> URL? {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            let candidate = url.appendingPathComponent("testdata/on-air-vectors.json")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            url.deleteLastPathComponent()
        }
        return nil
    }
}
