// Copyright 2026 Josh Howard
// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct COTChat: Equatable, Codable {
    public var roomID: String
    public var room: String
    public var senderCallsign: String
    public var senderUID: String
    public var recipientUID: String

    public init(roomID: String, room: String, senderCallsign: String, senderUID: String, recipientUID: String) {
        self.roomID = roomID
        self.room = room
        self.senderCallsign = senderCallsign
        self.senderUID = senderUID
        self.recipientUID = recipientUID
    }
}

public struct COTBridgeTag: Equatable, Codable {
    public var origin: String
    public var sources: String
    public var txid: String?

    public init(origin: String, sources: String, txid: String? = nil) {
        self.origin = origin
        self.sources = sources
        self.txid = txid
    }
}

public struct COTEvent: Equatable, Codable {
    public var uid: String
    public var type: String
    public var time: Date
    public var start: Date
    public var stale: Date
    public var how: String
    public var latitude: Double
    public var longitude: Double
    public var hae: Double
    public var ce: Double
    public var le: Double
    public var callsign: String
    public var remarks: String
    public var courseDegrees: Double?
    public var speedMetersPerSecond: Double?
    public var chat: COTChat?
    public var bridge: COTBridgeTag?

    public var isChat: Bool { chat != nil || type == "b-t-f" }
    public var isAtom: Bool { type.hasPrefix("a-") && chat == nil }

    public var xml: String { COTXML.render(self) }

    public init(
        uid: String,
        type: String,
        time: Date,
        start: Date? = nil,
        stale: Date,
        how: String,
        latitude: Double,
        longitude: Double,
        hae: Double = 9_999_999,
        ce: Double = 9_999_999,
        le: Double = 9_999_999,
        callsign: String,
        remarks: String = "",
        courseDegrees: Double? = nil,
        speedMetersPerSecond: Double? = nil,
        chat: COTChat? = nil,
        bridge: COTBridgeTag? = nil
    ) {
        self.uid = uid
        self.type = type
        self.time = time
        self.start = start ?? time
        self.stale = stale
        self.how = how
        self.latitude = latitude
        self.longitude = longitude
        self.hae = hae
        self.ce = ce
        self.le = le
        self.callsign = callsign
        self.remarks = remarks
        self.courseDegrees = courseDegrees
        self.speedMetersPerSecond = speedMetersPerSecond
        self.chat = chat
        self.bridge = bridge
    }
}

/// Best-effort APRS symbol to MIL-STD-2525 type. Friendly blue icons so a
/// ham station reads as a teammate on an iTAK map. This is not a certified
/// 2525 implementation and it is not the aprscot table.
public enum SymbolMap {
    public static func cotType(symbolTable _: String, symbol: String) -> String {
        switch symbol.first?.asciiValue {
        case UInt8(ascii: "["), UInt8(ascii: "b"):
            return "a-f-G-U-C-I"
        case UInt8(ascii: ">"), UInt8(ascii: "k"), UInt8(ascii: "j"),
             UInt8(ascii: "v"), UInt8(ascii: "<"):
            return "a-f-G-E-V-C"
        case UInt8(ascii: "s"), UInt8(ascii: "Y"):
            return "a-f-S"
        case UInt8(ascii: "^"), UInt8(ascii: "O"), UInt8(ascii: "'"):
            return "a-f-A"
        case UInt8(ascii: "-"), UInt8(ascii: "r"):
            return "a-f-G-I"
        default:
            return "a-f-G-U-C"
        }
    }
}

public enum APRSCOT {
    public static let unknownAltitude = 9_999_999.0

    public static func stationUID(base: String, ssid: Int) -> String {
        "APRS-\(Callsign.display(base: base, ssid: ssid))"
    }

    public static func objectUID(name: String, item: Bool) -> String {
        let prefix = item ? "APRS-ITEM-" : "APRS-OBJ-"
        let cleaned = name.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        return prefix + (cleaned.isEmpty ? "OBJECT" : cleaned)
    }

    public static func callsign(fromUID uid: String) -> String? {
        guard uid.hasPrefix("APRS-"), !uid.hasPrefix("APRS-OBJ-"), !uid.hasPrefix("APRS-ITEM-") else {
            return nil
        }
        let rest = String(uid.dropFirst("APRS-".count))
        return Callsign.parse(rest) == nil ? nil : rest
    }

    public static func positionEvent(
        position: APRSPosition,
        callsign: String,
        uid: String,
        now: Date,
        staleAfter: TimeInterval,
        origin: String,
        sources: String,
        txid: String?
    ) -> COTEvent {
        let speed = position.speedKnots.map { $0 * 1852.0 / 3600.0 }
        return COTEvent(
            uid: uid,
            type: SymbolMap.cotType(symbolTable: position.symbolTable, symbol: position.symbol),
            time: position.timestamp ?? now,
            stale: (position.timestamp ?? now).addingTimeInterval(staleAfter),
            how: "m-g",
            latitude: position.latitude,
            longitude: position.longitude,
            hae: position.altitudeMeters ?? unknownAltitude,
            callsign: callsign,
            remarks: position.comment,
            courseDegrees: position.courseDegrees,
            speedMetersPerSecond: speed,
            bridge: COTBridgeTag(origin: origin, sources: sources, txid: txid)
        )
    }

    public static func chatEvent(
        from: String,
        fromUID: String,
        to: String,
        toUID: String,
        text: String,
        messageID: String,
        latitude: Double,
        longitude: Double,
        now: Date,
        staleAfter: TimeInterval
    ) -> COTEvent {
        let chat = COTChat(
            roomID: toUID,
            room: to,
            senderCallsign: from,
            senderUID: fromUID,
            recipientUID: toUID
        )
        return COTEvent(
            uid: "GeoChat.\(fromUID).\(toUID).\(messageID)",
            type: "b-t-f",
            time: now,
            stale: now.addingTimeInterval(staleAfter),
            how: "h-g-i-g-o",
            latitude: latitude,
            longitude: longitude,
            callsign: from,
            remarks: text,
            chat: chat,
            bridge: COTBridgeTag(origin: "rf", sources: "rf", txid: "msg-\(fromUID)-\(messageID)")
        )
    }
}

public struct GeoChatRoute: Equatable {
    public var senderCallsign: String
    public var recipientCallsign: String?
    public var text: String
    public var allChat: Bool
}

public enum GeoChat {
    public static func route(_ event: COTEvent) -> GeoChatRoute? {
        guard event.isChat else { return nil }
        let sender = event.chat?.senderCallsign.isEmpty == false ? event.chat!.senderCallsign : event.callsign
        guard !sender.isEmpty else { return nil }
        let room = (event.chat?.room ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let roomID = event.chat?.roomID ?? ""
        let all = room.lowercased().contains("all chat") || roomID.lowercased().contains("all chat")
        var recipient: String?
        if let fromUID = APRSCOT.callsign(fromUID: event.chat?.recipientUID ?? "") {
            recipient = fromUID
        } else if let parsed = Callsign.parse(room) {
            recipient = Callsign.display(base: parsed.base, ssid: parsed.ssid)
        } else if let parsed = Callsign.parse(event.chat?.recipientUID ?? "") {
            recipient = Callsign.display(base: parsed.base, ssid: parsed.ssid)
        }
        return GeoChatRoute(
            senderCallsign: sender,
            recipientCallsign: all ? nil : recipient,
            text: event.remarks,
            allChat: all
        )
    }
}

public enum COTInbound: Equatable {
    case event(COTEvent)
    case protobuf(length: Int)
}

/// Incremental TAK stream. CoT XML is what we speak. A leading 0xBF frame is
/// the TAK protobuf envelope; it is consumed so it cannot desync the XML parser.
public final class COTByteStream {
    private var buffer = Data()

    public init() {}

    public func reset() { buffer.removeAll(keepingCapacity: true) }

    public func append(_ data: Data) -> [COTInbound] {
        buffer.append(data)
        var inbound: [COTInbound] = []
        while !buffer.isEmpty {
            if buffer.first == 0xBF {
                guard let consumed = consumeProtobuf() else { break }
                inbound.append(.protobuf(length: consumed))
                continue
            }
            if let first = buffer.first, first == 0x20 || first == 0x0A || first == 0x0D || first == 0x09 {
                buffer.removeFirst()
                continue
            }
            guard buffer.first == UInt8(ascii: "<") else {
                if let next = buffer.firstIndex(of: UInt8(ascii: "<")) ?? buffer.firstIndex(of: 0xBF) {
                    buffer.removeSubrange(buffer.startIndex..<next)
                    continue
                }
                if buffer.count > 4096 { buffer.removeAll(keepingCapacity: true) }
                break
            }
            guard let xml = String(data: buffer, encoding: .utf8) ?? String(data: buffer, encoding: .isoLatin1) else {
                break
            }
            guard let end = endOfFirstEvent(in: xml) else { break }
            let chunk = String(xml[..<end])
            if let event = COTXML.parseEvents(in: chunk).first {
                inbound.append(.event(event))
            }
            let used = Data(chunk.utf8).count
            if used == 0 || used > buffer.count {
                buffer.removeAll(keepingCapacity: true)
                break
            }
            buffer.removeFirst(used)
        }
        return inbound
    }

    private func consumeProtobuf() -> Int? {
        let bytes = [UInt8](buffer)
        guard bytes.count >= 2 else { return nil }
        var value = 0
        var shift = 0
        var index = 1
        while index < bytes.count && index < 6 {
            let byte = Int(bytes[index])
            value |= (byte & 0x7F) << shift
            index += 1
            if byte & 0x80 == 0 {
                let total = index + value
                guard value >= 0, value < 2_000_000, total <= bytes.count else {
                    if total > bytes.count && value < 2_000_000 { return nil }
                    buffer.removeFirst()
                    return 0
                }
                buffer.removeFirst(total)
                return value
            }
            shift += 7
        }
        return nil
    }
}

public enum COTXML {
    public static func render(_ event: COTEvent) -> String {
        let point = """
        <point lat="\(formatNumber(event.latitude))" lon="\(formatNumber(event.longitude))" hae="\(formatAltitude(event.hae))" ce="\(formatAltitude(event.ce))" le="\(formatAltitude(event.le))"/>
        """
        var detail = "<contact callsign=\"\(xmlEscape(event.callsign))\"/>"
        if !event.remarks.isEmpty {
            detail += "<remarks>\(xmlEscape(event.remarks))</remarks>"
        }
        if event.courseDegrees != nil || event.speedMetersPerSecond != nil {
            let course = formatNumber(event.courseDegrees ?? 0)
            let speed = formatNumber(event.speedMetersPerSecond ?? 0)
            detail += "<track course=\"\(course)\" speed=\"\(speed)\"/>"
        }
        if let chat = event.chat {
            detail += """
            <__chat id="\(xmlEscape(chat.roomID))" chatroom="\(xmlEscape(chat.room))" senderCallsign="\(xmlEscape(chat.senderCallsign))" groupOwner="false"><chatgrp id="\(xmlEscape(chat.roomID))" uid0="\(xmlEscape(chat.senderUID))" uid1="\(xmlEscape(chat.recipientUID))"/></__chat><link uid="\(xmlEscape(chat.senderUID))" type="\(xmlEscape(event.type))" relation="p-p"/>
            """
        }
        if let bridge = event.bridge {
            let tx = bridge.txid.map { " txid=\"\(xmlEscape($0))\"" } ?? ""
            detail += "<uvbridge origin=\"\(xmlEscape(bridge.origin))\" sources=\"\(xmlEscape(bridge.sources))\"\(tx)/>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>\
        <event version="2.0" uid="\(xmlEscape(event.uid))" type="\(xmlEscape(event.type))" time="\(COTDate.format(event.time))" start="\(COTDate.format(event.start))" stale="\(COTDate.format(event.stale))" how="\(xmlEscape(event.how))">\
        \(point)<detail>\(detail)</detail></event>
        """
    }

    public static func parseEvents(in xml: String) -> [COTEvent] {
        var events: [COTEvent] = []
        var rest = xml[...]
        while let start = rest.range(of: "<event") {
            guard let end = rest.range(of: "</event>", range: start.lowerBound..<rest.endIndex) else { break }
            let chunk = rest[start.lowerBound..<end.upperBound]
            if let event = parseOne(String(chunk)) {
                events.append(event)
            }
            rest = rest[end.upperBound...]
        }
        return events
    }

    static func parseOne(_ xml: String) -> COTEvent? {
        guard let open = openingTag("event", in: xml) else { return nil }
        let attrs = attributes(open)
        guard let uid = attrs["uid"], let type = attrs["type"] else { return nil }
        let now = Date()
        let time = attrs["time"].flatMap(COTDate.parse) ?? now
        let start = attrs["start"].flatMap(COTDate.parse) ?? time
        let stale = attrs["stale"].flatMap(COTDate.parse) ?? time.addingTimeInterval(1800)
        let point = attributes(openingTag("point", in: xml) ?? "")
        let contact = attributes(openingTag("contact", in: xml) ?? "")
        let track = attributes(openingTag("track", in: xml) ?? "")
        let bridgeTag = attributes(openingTag("uvbridge", in: xml) ?? "")
        let chatTag = attributes(openingTag("__chat", in: xml) ?? "")
        let groupTag = attributes(openingTag("chatgrp", in: xml) ?? "")
        var chat: COTChat?
        if !chatTag.isEmpty || xml.contains("__chat") {
            chat = COTChat(
                roomID: chatTag["id"] ?? "",
                room: chatTag["chatroom"] ?? "",
                senderCallsign: chatTag["senderCallsign"] ?? contact["callsign"] ?? "",
                senderUID: groupTag["uid0"] ?? "",
                recipientUID: groupTag["uid1"] ?? chatTag["id"] ?? ""
            )
        }
        var bridge: COTBridgeTag?
        if !bridgeTag.isEmpty {
            bridge = COTBridgeTag(origin: bridgeTag["origin"] ?? "", sources: bridgeTag["sources"] ?? "", txid: bridgeTag["txid"])
        }
        return COTEvent(
            uid: xmlUnescape(uid),
            type: xmlUnescape(type),
            time: time,
            start: start,
            stale: stale,
            how: xmlUnescape(attrs["how"] ?? "m-g"),
            latitude: Double(point["lat"] ?? "") ?? 0,
            longitude: Double(point["lon"] ?? "") ?? 0,
            hae: Double(point["hae"] ?? "") ?? APRSCOT.unknownAltitude,
            ce: Double(point["ce"] ?? "") ?? APRSCOT.unknownAltitude,
            le: Double(point["le"] ?? "") ?? APRSCOT.unknownAltitude,
            callsign: xmlUnescape(contact["callsign"] ?? ""),
            remarks: xmlUnescape(elementText("remarks", in: xml) ?? ""),
            courseDegrees: track["course"].flatMap(Double.init),
            speedMetersPerSecond: track["speed"].flatMap(Double.init),
            chat: chat,
            bridge: bridge
        )
    }

    static func openingTag(_ name: String, in xml: String) -> String? {
        guard let start = xml.range(of: "<\(name)") else { return nil }
        guard let end = xml[start.lowerBound...].firstIndex(of: ">") else { return nil }
        return String(xml[start.lowerBound...end])
    }

    static func elementText(_ name: String, in xml: String) -> String? {
        guard let openEnd = xml.range(of: "<\(name)")?.upperBound, let close = xml.range(of: "</\(name)>") else {
            return nil
        }
        guard let contentStart = xml[openEnd...].firstIndex(of: ">") else { return nil }
        let start = xml.index(after: contentStart)
        guard start <= close.lowerBound else { return nil }
        return String(xml[start..<close.lowerBound])
    }

    static func attributes(_ tag: String) -> [String: String] {
        var result: [String: String] = [:]
        let chars = Array(tag)
        var index = 0
        func skipSpace() {
            while index < chars.count, chars[index].isWhitespace { index += 1 }
        }
        while index < chars.count {
            skipSpace()
            guard index < chars.count, chars[index] != "<", chars[index] != ">", chars[index] != "/" else {
                index += 1
                continue
            }
            let nameStart = index
            while index < chars.count, chars[index].isLetter || chars[index].isNumber || chars[index] == "_" || chars[index] == ":" || chars[index] == "-" {
                index += 1
            }
            let name = String(chars[nameStart..<index])
            skipSpace()
            guard index < chars.count, chars[index] == "=" else { continue }
            index += 1
            skipSpace()
            guard index < chars.count, chars[index] == "\"" || chars[index] == "'" else { continue }
            let quote = chars[index]
            index += 1
            let valueStart = index
            while index < chars.count, chars[index] != quote { index += 1 }
            result[name] = String(chars[valueStart..<index])
            if index < chars.count { index += 1 }
        }
        return result
    }
}

enum COTDate {
    static func format(_ date: Date) -> String {
        let interval = date.timeIntervalSince1970
        var whole = floor(interval)
        var millis = Int((interval - whole) * 1000.0 + 1e-6)
        if millis >= 1000 {
            millis -= 1000
            whole += 1
        }
        if millis < 0 { millis = 0 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date(timeIntervalSince1970: whole))
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ",
            parts.year ?? 1970,
            parts.month ?? 1,
            parts.day ?? 1,
            parts.hour ?? 0,
            parts.minute ?? 0,
            parts.second ?? 0,
            millis
        )
    }

    static func parse(_ text: String) -> Date? {
        let bytes = Array(text.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        guard bytes.count >= 20 else { return nil }
        func number(_ start: Int, _ count: Int) -> Int? {
            var value = 0
            for offset in 0..<count {
                let index = start + offset
                guard index < bytes.count, bytes[index] >= 48, bytes[index] <= 57 else { return nil }
                value = value * 10 + Int(bytes[index] - 48)
            }
            return value
        }
        guard let year = number(0, 4), bytes[4] == UInt8(ascii: "-"),
              let month = number(5, 2), bytes[7] == UInt8(ascii: "-"),
              let day = number(8, 2), bytes[10] == UInt8(ascii: "T"),
              let hour = number(11, 2), bytes[13] == UInt8(ascii: ":"),
              let minute = number(14, 2), bytes[16] == UInt8(ascii: ":"),
              let second = number(17, 2)
        else { return nil }
        var millis = 0
        if bytes.count > 19, bytes[19] == UInt8(ascii: ".") {
            var frac = 0
            var digits = 0
            var index = 20
            while index < bytes.count, bytes[index] >= 48, bytes[index] <= 57, digits < 3 {
                frac = frac * 10 + Int(bytes[index] - 48)
                digits += 1
                index += 1
            }
            while digits < 3 {
                frac *= 10
                digits += 1
            }
            millis = frac
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = hour
        parts.minute = minute
        parts.second = second
        parts.nanosecond = millis * 1_000_000
        return calendar.date(from: parts)
    }
}

func xmlEscape(_ text: String) -> String {
    text
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&apos;")
}

func xmlUnescape(_ text: String) -> String {
    var result = ""
    var rest = text[...]
    while let amp = rest.firstIndex(of: "&") {
        result += rest[..<amp]
        let tail = rest[amp...]
        if tail.hasPrefix("&amp;") {
            result += "&"
            rest = tail.dropFirst(5)
        } else if tail.hasPrefix("&lt;") {
            result += "<"
            rest = tail.dropFirst(4)
        } else if tail.hasPrefix("&gt;") {
            result += ">"
            rest = tail.dropFirst(4)
        } else if tail.hasPrefix("&quot;") {
            result += "\""
            rest = tail.dropFirst(6)
        } else if tail.hasPrefix("&apos;") {
            result += "'"
            rest = tail.dropFirst(6)
        } else {
            result += "&"
            rest = tail.dropFirst()
        }
    }
    result += rest
    return result
}

private func formatNumber(_ value: Double) -> String {
    String(format: "%.6f", value)
}

private func formatAltitude(_ value: Double) -> String {
    if value >= 9_999_999 { return "9999999.0" }
    return String(format: "%.1f", value)
}

private func endOfFirstEvent(in xml: String) -> String.Index? {
    guard let start = xml.range(of: "<event") else { return nil }
    var depth = 0
    var index = start.lowerBound
    while index < xml.endIndex {
        if xml[index...].hasPrefix("<event") {
            depth += 1
            index = xml.index(index, offsetBy: 6, limitedBy: xml.endIndex) ?? xml.endIndex
            continue
        }
        if xml[index...].hasPrefix("</event>") {
            depth -= 1
            let next = xml.index(index, offsetBy: 8, limitedBy: xml.endIndex) ?? xml.endIndex
            if depth == 0 { return next }
            index = next
            continue
        }
        index = xml.index(after: index)
    }
    return nil
}
