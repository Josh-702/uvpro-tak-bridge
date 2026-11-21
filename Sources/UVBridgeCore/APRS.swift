// Copyright 2026 Josh Howard
// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct APRSPosition: Equatable {
    public var latitude: Double
    public var longitude: Double
    public var symbolTable: String
    public var symbol: String
    public var comment: String
    public var courseDegrees: Double?
    public var speedKnots: Double?
    public var altitudeMeters: Double?
    public var timestamp: Date?
    public var messaging: Bool
    public var compressed: Bool
    public var micE: Bool
    public var micEMessage: String?

    public init(
        latitude: Double,
        longitude: Double,
        symbolTable: String = "/",
        symbol: String = "[",
        comment: String = "",
        courseDegrees: Double? = nil,
        speedKnots: Double? = nil,
        altitudeMeters: Double? = nil,
        timestamp: Date? = nil,
        messaging: Bool = false,
        compressed: Bool = false,
        micE: Bool = false,
        micEMessage: String? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.symbolTable = symbolTable
        self.symbol = symbol
        self.comment = comment
        self.courseDegrees = courseDegrees
        self.speedKnots = speedKnots
        self.altitudeMeters = altitudeMeters
        self.timestamp = timestamp
        self.messaging = messaging
        self.compressed = compressed
        self.micE = micE
        self.micEMessage = micEMessage
    }
}

public struct APRSObjectReport: Equatable {
    public var name: String
    public var live: Bool
    public var isItem: Bool
    public var position: APRSPosition
}

public struct APRSMessage: Equatable {
    public enum Kind: Equatable {
        case text(String, id: String?)
        case ack(String)
        case reject(String)
    }

    public var addressee: String
    public var kind: Kind

    public var isBulletin: Bool {
        let name = addressee.uppercased().filter { !$0.isWhitespace }
        if name.hasPrefix("BLN") || name.hasPrefix("NWS") { return true }
        return name == "CQ" || name == "QST" || name == "ALL"
    }
}

public struct APRSStatus: Equatable {
    public var text: String
    public var timestamp: Date?
}

public enum APRSBody: Equatable {
    case position(APRSPosition)
    case object(APRSObjectReport)
    case status(APRSStatus)
    case message(APRSMessage)
    case raw(String)
}

public struct APRSPacket: Equatable {
    public var source: AX25Address
    public var destination: AX25Address
    public var path: [AX25Address]
    public var body: APRSBody
    public var thirdParty: Bool

    public var summary: String {
        let head = "\(source.display)>\(destination.display)"
        switch body {
        case .position(let position):
            return "\(head) \(APRS.coordinateText(position)) \(position.symbolTable)\(position.symbol) \(position.comment)"
        case .object(let object):
            let kind = object.isItem ? "item" : "object"
            return "\(head) \(kind) \(object.name) \(APRS.coordinateText(object.position))"
        case .status(let status):
            return "\(head) status \(status.text)"
        case .message(let message):
            switch message.kind {
            case .text(let text, let id):
                return "\(head) msg \(message.addressee): \(text)\(id.map { " {\($0)" } ?? "")"
            case .ack(let id):
                return "\(head) ack \(message.addressee) \(id)"
            case .reject(let id):
                return "\(head) rej \(message.addressee) \(id)"
            }
        case .raw(let text):
            return "\(head) raw \(text)"
        }
    }
}

public enum APRS {
    public static func parse(frame: AX25Frame, now: Date = Date()) -> APRSPacket {
        let body = parseBody(bytes: [UInt8](frame.info), now: now, depth: 0)
            ?? .raw(APRSASCII.preview(frame.info))
        return APRSPacket(
            source: frame.source,
            destination: frame.destination,
            path: frame.digipeaters,
            body: body,
            thirdParty: false
        )
    }

    public static func coordinateText(_ position: APRSPosition) -> String {
        String(format: "%.5f, %.5f", position.latitude, position.longitude)
    }

    static func parseBody(bytes: [UInt8], now: Date, depth: Int) -> APRSBody? {
        guard let first = bytes.first else { return nil }
        switch first {
        case UInt8(ascii: "!"), UInt8(ascii: "="):
            let messaging = first == UInt8(ascii: "=")
            guard let position = parsePosition(bytes: bytes, index: 1, messaging: messaging, timestamp: nil) else {
                return nil
            }
            return .position(position)
        case UInt8(ascii: "/"), UInt8(ascii: "@"):
            let messaging = first == UInt8(ascii: "@")
            guard APRSTime.looksLikeTimestamp(bytes, at: 1),
                  let stamp = APRSTime.parse(Array(bytes[1..<8]), now: now)
            else { return nil }
            guard let position = parsePosition(bytes: bytes, index: 8, messaging: messaging, timestamp: stamp) else {
                return nil
            }
            return .position(position)
        case UInt8(ascii: "'"), UInt8(ascii: "`"), 0x1C, 0x1D:
            return nil
        case UInt8(ascii: ";"):
            guard let object = parseObject(bytes: bytes, now: now, item: false) else { return nil }
            return .object(object)
        case UInt8(ascii: ")"):
            guard let object = parseObject(bytes: bytes, now: now, item: true) else { return nil }
            return .object(object)
        case UInt8(ascii: ":"):
            guard let message = parseMessage(bytes: bytes) else { return nil }
            return .message(message)
        case UInt8(ascii: ">"):
            guard let status = parseStatus(bytes: bytes, now: now) else { return nil }
            return .status(status)
        case UInt8(ascii: "}"):
            guard depth == 0, let inner = parseThirdParty(bytes: bytes, now: now) else { return nil }
            return inner
        default:
            return nil
        }
    }

    static func parsePosition(bytes: [UInt8], index: Int, messaging: Bool, timestamp: Date?) -> APRSPosition? {
        guard index < bytes.count else { return nil }
        if bytes[index].isASCIIDigit {
            return parseUncompressed(bytes: bytes, index: index, messaging: messaging, timestamp: timestamp)
        }
        return parseCompressed(bytes: bytes, index: index, messaging: messaging, timestamp: timestamp)
    }

    static func parseUncompressed(bytes: [UInt8], index: Int, messaging: Bool, timestamp: Date?) -> APRSPosition? {
        guard index + 19 <= bytes.count else { return nil }
        guard let latitude = APRSLatLon.parse(bytes[index..<(index + 8)], degreeDigits: 2, positive: UInt8(ascii: "N"), negative: UInt8(ascii: "S")),
              let longitude = APRSLatLon.parse(bytes[(index + 9)..<(index + 18)], degreeDigits: 3, positive: UInt8(ascii: "E"), negative: UInt8(ascii: "W"))
        else { return nil }
        let table = bytes[index + 8]
        let symbol = bytes[index + 18]
        let commentBytes = Array(bytes.dropFirst(index + 19))
        var position = APRSPosition(
            latitude: latitude,
            longitude: longitude,
            symbolTable: APRSASCII.symbol(table),
            symbol: APRSASCII.symbol(symbol),
            comment: APRSASCII.string(commentBytes),
            timestamp: timestamp,
            messaging: messaging
        )
        enrich(&position, comment: commentBytes)
        return position
    }

    static func parseCompressed(bytes: [UInt8], index: Int, messaging: Bool, timestamp: Date?) -> APRSPosition? {
        guard index + 13 <= bytes.count else { return nil }
        guard let latN = Base91.decode(bytes[(index + 1)..<(index + 5)]),
              let lonN = Base91.decode(bytes[(index + 5)..<(index + 9)])
        else { return nil }
        let latitude = 90.0 - Double(latN) / 380926.0
        let longitude = -180.0 + Double(lonN) / 190463.0
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        let motion = CompressedMotion.decode(
            courseByte: bytes[index + 10],
            speedByte: bytes[index + 11],
            typeByte: bytes[index + 12]
        )
        let commentBytes = Array(bytes.dropFirst(index + 13))
        var position = APRSPosition(
            latitude: latitude,
            longitude: longitude,
            symbolTable: APRSASCII.symbol(bytes[index]),
            symbol: APRSASCII.symbol(bytes[index + 9]),
            comment: APRSASCII.string(commentBytes),
            courseDegrees: motion.courseDegrees,
            speedKnots: motion.speedKnots,
            altitudeMeters: motion.altitudeFeet.map { $0 * 0.3048 },
            timestamp: timestamp,
            messaging: messaging,
            compressed: true
        )
        enrich(&position, comment: commentBytes)
        return position
    }

    static func enrich(_ position: inout APRSPosition, comment: [UInt8]) {
        if comment.count >= 7, comment[3] == UInt8(ascii: "/") {
            let courseText = APRSASCII.string(comment[0..<3])
            let speedText = APRSASCII.string(comment[4..<7])
            if courseText.allSatisfy(\.isNumber), speedText.allSatisfy(\.isNumber),
               let course = Int(courseText), let speed = Int(speedText), course <= 360 {
                position.courseDegrees = Double(course)
                position.speedKnots = Double(speed)
            }
        }
        if let range = APRSASCII.string(comment).range(of: "/A=") {
            let tail = APRSASCII.string(comment)[range.upperBound...]
            let digits = tail.prefix(6)
            if digits.count == 6, digits.allSatisfy(\.isNumber), let feet = Int(digits) {
                position.altitudeMeters = Double(feet) * 0.3048
            }
        }
    }

    static func parseObject(bytes: [UInt8], now: Date, item: Bool) -> APRSObjectReport? {
        if item {
            guard bytes.count > 4 else { return nil }
            var end = 1
            while end < bytes.count, end <= 10, bytes[end] != UInt8(ascii: "!"), bytes[end] != UInt8(ascii: "_") {
                end += 1
            }
            guard end < bytes.count, (3...9).contains(end - 1) else { return nil }
            let name = APRSASCII.string(bytes[1..<end]).trimmingCharacters(in: .whitespaces)
            let live = bytes[end] == UInt8(ascii: "!")
            var index = end + 1
            var stamp: Date?
            if APRSTime.looksLikeTimestamp(bytes, at: index), index + 7 <= bytes.count {
                stamp = APRSTime.parse(Array(bytes[index..<(index + 7)]), now: now)
                index += 7
            }
            guard var position = parsePosition(bytes: bytes, index: index, messaging: false, timestamp: stamp) else {
                return nil
            }
            position.timestamp = stamp
            return APRSObjectReport(name: name, live: live, isItem: true, position: position)
        }
        guard bytes.count >= 1 + 9 + 1 + 19 else { return nil }
        let name = APRSASCII.string(bytes[1..<10]).trimmingCharacters(in: .whitespaces)
        guard bytes[10] == UInt8(ascii: "*") || bytes[10] == UInt8(ascii: "_") else { return nil }
        let live = bytes[10] == UInt8(ascii: "*")
        var index = 11
        var stamp: Date?
        if APRSTime.looksLikeTimestamp(bytes, at: index) {
            stamp = APRSTime.parse(Array(bytes[index..<(index + 7)]), now: now)
            index += 7
        }
        guard var position = parsePosition(bytes: bytes, index: index, messaging: false, timestamp: stamp) else {
            return nil
        }
        position.timestamp = stamp
        return APRSObjectReport(name: name, live: live, isItem: false, position: position)
    }

    static func parseStatus(bytes: [UInt8], now: Date) -> APRSStatus? {
        var index = 1
        var stamp: Date?
        if APRSTime.looksLikeTimestamp(bytes, at: index) {
            stamp = APRSTime.parse(Array(bytes[index..<(index + 7)]), now: now)
            index += 7
        }
        let text = APRSASCII.string(bytes.dropFirst(index)).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return APRSStatus(text: text, timestamp: stamp)
    }

    static func parseMessage(bytes: [UInt8]) -> APRSMessage? {
        guard bytes.count >= 11, bytes[10] == UInt8(ascii: ":") else { return nil }
        let addressee = APRSASCII.string(bytes[1..<10]).trimmingCharacters(in: .whitespaces)
        guard !addressee.isEmpty else { return nil }
        let body = APRSASCII.string(bytes.dropFirst(11))
        if body.hasPrefix("ack") {
            let id = String(body.dropFirst(3))
            guard !id.isEmpty, id.count <= 5, id.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
            return APRSMessage(addressee: addressee, kind: .ack(id))
        }
        if body.hasPrefix("rej") {
            let id = String(body.dropFirst(3))
            guard !id.isEmpty, id.count <= 5, id.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
            return APRSMessage(addressee: addressee, kind: .reject(id))
        }
        var text = body
        var msgid: String?
        if let brace = text.lastIndex(of: "{") {
            let suffix = text[text.index(after: brace)...]
            if (1...5).contains(suffix.count), suffix.allSatisfy({ $0.isLetter || $0.isNumber }) {
                msgid = String(suffix)
                text = String(text[..<brace])
            }
        }
        return APRSMessage(addressee: addressee, kind: .text(text, id: msgid))
    }

    static func parseThirdParty(bytes: [UInt8], now: Date) -> APRSBody? {
        let text = APRSASCII.string(bytes.dropFirst())
        guard let colon = text.firstIndex(of: ":"), let gt = text.firstIndex(of: ">"), gt < colon else {
            return nil
        }
        let sourceRaw = String(text[..<gt])
        let header = text[text.index(after: gt)..<colon]
        let payload = String(text[text.index(after: colon)...])
        guard looseAddress(sourceRaw) != nil else { return nil }
        let pieces = header.split(separator: ",", omittingEmptySubsequences: true)
        guard let destRaw = pieces.first, looseAddress(String(destRaw)) != nil else { return nil }
        let info = Array(payload.utf8)
        guard let body = parseBody(bytes: info, now: now, depth: 1) else { return nil }
        if case .raw = body { return nil }
        return body
    }

    /// Full packet parse that uses the inner callsign when the frame is third-party.
    public static func parseHeard(frame: AX25Frame, now: Date = Date()) -> APRSPacket {
        let bytes = [UInt8](frame.info)
        if bytes.first == UInt8(ascii: "}"),
           let packet = parseThirdPartyPacket(bytes: bytes, outer: frame, now: now) {
            return packet
        }
        if let mic = MicE.parse(info: bytes, destination: frame.destination) {
            return APRSPacket(
                source: frame.source,
                destination: frame.destination,
                path: frame.digipeaters,
                body: .position(mic),
                thirdParty: false
            )
        }
        return parse(frame: frame, now: now)
    }

    private static func parseThirdPartyPacket(bytes: [UInt8], outer: AX25Frame, now: Date) -> APRSPacket? {
        let text = APRSASCII.string(bytes.dropFirst())
        guard let colon = text.firstIndex(of: ":"), let gt = text.firstIndex(of: ">"), gt < colon else {
            return nil
        }
        let sourceRaw = String(text[..<gt])
        let header = text[text.index(after: gt)..<colon]
        let payload = Array(text[text.index(after: colon)...].utf8)
        guard let source = looseAddress(sourceRaw) else { return nil }
        let pieces = header.split(separator: ",")
        guard let destRaw = pieces.first, let destination = looseAddress(String(destRaw).replacingOccurrences(of: "*", with: "")) else {
            return nil
        }
        let path = pieces.dropFirst().compactMap { piece -> AX25Address? in
            var token = String(piece)
            let repeated = token.hasSuffix("*")
            if repeated { token.removeLast() }
            guard var address = looseAddress(token) else { return nil }
            address.repeated = repeated
            return address
        }
        let body: APRSBody
        if let mic = MicE.parse(info: payload, destination: destination) {
            body = .position(mic)
        } else if let parsed = parseBody(bytes: payload, now: now, depth: 1) {
            body = parsed
        } else {
            return nil
        }
        return APRSPacket(source: source, destination: destination, path: path, body: body, thirdParty: true)
    }

    static func looseAddress(_ raw: String) -> AX25Address? {
        let cleaned = raw.trimmingCharacters(in: .whitespaces).uppercased().replacingOccurrences(of: "*", with: "")
        if let parsed = Callsign.parse(cleaned) {
            return AX25Address(call: parsed.base, ssid: parsed.ssid)
        }
        let parts = cleaned.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2 else { return nil }
        let call = String(parts[0])
        guard (1...6).contains(call.count), call.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            return nil
        }
        var ssid = 0
        if parts.count == 2 {
            guard let value = Int(parts[1]), (0...15).contains(value) else { return nil }
            ssid = value
        }
        return AX25Address(call: call, ssid: ssid)
    }
}

public enum APRSBuilder {
    public static let defaultToCall = "APRS"

    public static func uncompressedPosition(
        latitude: Double,
        longitude: Double,
        symbolTable: Character = "/",
        symbol: Character = "[",
        comment: String = "",
        messaging: Bool = true,
        courseDegrees: Int? = nil,
        speedKnots: Int? = nil
    ) -> String? {
        guard let formatted = APRSLatLon.format(latitude: latitude, longitude: longitude) else { return nil }
        guard let table = symbolTable.asciiValue, let code = symbol.asciiValue else { return nil }
        var text = (messaging ? "=" : "!") + formatted.lat + String(UnicodeScalar(table)) + formatted.lon + String(UnicodeScalar(code))
        if let courseDegrees, let speedKnots, (0...360).contains(courseDegrees), (0...999).contains(speedKnots) {
            text += String(format: "%03d/%03d", courseDegrees, speedKnots)
        }
        text += APRSASCII.asciiOnly(comment)
        guard text.utf8.count <= 256 else { return nil }
        return text
    }

    public static func compressedPosition(
        latitude: Double,
        longitude: Double,
        symbolTable: Character = "/",
        symbol: Character = "[",
        comment: String = "",
        messaging: Bool = true,
        courseDegrees: Double? = nil,
        speedKnots: Double? = nil
    ) -> String? {
        guard let encoded = CompressedMotion.encodePosition(
            latitude: latitude,
            longitude: longitude,
            symbolTable: symbolTable,
            symbol: symbol,
            courseDegrees: courseDegrees,
            speedKnots: speedKnots
        ) else { return nil }
        let text = (messaging ? "=" : "!") + encoded + APRSASCII.asciiOnly(comment)
        guard text.utf8.count <= 256 else { return nil }
        return text
    }

    public static func status(_ text: String) -> String? {
        let clean = APRSASCII.asciiOnly(text)
        guard !clean.isEmpty, clean.utf8.count <= 200 else { return nil }
        return ">" + clean
    }

    public static func message(to addressee: String, body: String, id: String?) -> String? {
        guard body.count <= 67, let padded = pad(addressee) else { return nil }
        var text = ":\(padded):\(APRSASCII.asciiOnly(body))"
        if let id {
            let clean = id.filter { $0.isLetter || $0.isNumber }
            guard (1...5).contains(clean.count) else { return nil }
            text += "{\(clean)"
        }
        return text
    }

    public static func ack(to addressee: String, id: String) -> String? {
        guard let padded = pad(addressee) else { return nil }
        let clean = id.filter { $0.isLetter || $0.isNumber }
        guard (1...5).contains(clean.count) else { return nil }
        return ":\(padded):ack\(clean)"
    }

    public static func object(
        name: String,
        latitude: Double,
        longitude: Double,
        live: Bool = true,
        symbolTable: Character = "/",
        symbol: Character = "-",
        comment: String = "",
        timestamp: Date? = nil
    ) -> String? {
        let trimmed = APRSASCII.asciiOnly(name).prefix(9)
        guard trimmed.count >= 1, let formatted = APRSLatLon.format(latitude: latitude, longitude: longitude) else {
            return nil
        }
        let padded = trimmed.padding(toLength: 9, withPad: " ", startingAt: 0)
        let flag = live ? "*" : "_"
        let stamp = timestamp.map { APRSTime.formatDHM($0) } ?? ""
        guard let table = symbolTable.asciiValue, let code = symbol.asciiValue else { return nil }
        return ";" + padded + flag + stamp + formatted.lat + String(UnicodeScalar(table)) + formatted.lon + String(UnicodeScalar(code)) + APRSASCII.asciiOnly(comment)
    }

    public static func item(
        name: String,
        latitude: Double,
        longitude: Double,
        live: Bool = true,
        symbolTable: Character = "/",
        symbol: Character = "[",
        comment: String = ""
    ) -> String? {
        let trimmed = String(APRSASCII.asciiOnly(name).prefix(9))
        guard (3...9).contains(trimmed.count), let formatted = APRSLatLon.format(latitude: latitude, longitude: longitude) else {
            return nil
        }
        guard let table = symbolTable.asciiValue, let code = symbol.asciiValue else { return nil }
        return ")" + trimmed + (live ? "!" : "_") + formatted.lat + String(UnicodeScalar(table)) + formatted.lon + String(UnicodeScalar(code)) + APRSASCII.asciiOnly(comment)
    }

    public static func pad(_ addressee: String) -> String? {
        let value = addressee.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard (1...9).contains(value.count) else { return nil }
        guard value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { return nil }
        return value.padding(toLength: 9, withPad: " ", startingAt: 0)
    }
}

enum APRSASCII {
    static func string<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        String(bytes.map { byte -> Character in
            if byte >= 0x20 && byte < 0x7F { return Character(UnicodeScalar(byte)) }
            return "?"
        })
    }

    static func preview(_ data: Data) -> String {
        string([UInt8](data))
    }

    static func symbol(_ byte: UInt8) -> String {
        if byte >= 0x20 && byte < 0x7F { return String(UnicodeScalar(byte)) }
        return "/"
    }

    static func asciiOnly(_ text: String) -> String {
        String(text.utf8.compactMap { byte -> Character? in
            guard byte >= 0x20 && byte < 0x7F else { return nil }
            return Character(UnicodeScalar(byte))
        })
    }
}

enum APRSLatLon {
    static func format(latitude: Double, longitude: Double) -> (lat: String, lon: String)? {
        guard (-90.0...90.0).contains(latitude), (-180.0...180.0).contains(longitude) else { return nil }
        return (
            formatHalf(latitude, width: 2, positive: "N", negative: "S"),
            formatHalf(longitude, width: 3, positive: "E", negative: "W")
        )
    }

    static func formatHalf(_ value: Double, width: Int, positive: String, negative: String) -> String {
        let hemisphere = value < 0 ? negative : positive
        var degrees = Int(abs(value))
        var hundredths = Int(((abs(value) - Double(degrees)) * 6000.0).rounded())
        if hundredths >= 6000 {
            hundredths -= 6000
            degrees += 1
        }
        let cap = width == 2 ? 90 : 180
        if degrees > cap {
            degrees = cap
            hundredths = 0
        }
        if degrees == cap { hundredths = 0 }
        let minutes = hundredths / 100
        let frac = hundredths % 100
        return String(format: "%0*d%02d.%02d", width, degrees, minutes, frac) + hemisphere
    }

    static func parse(
        _ bytes: ArraySlice<UInt8>,
        degreeDigits: Int,
        positive: UInt8,
        negative: UInt8
    ) -> Double? {
        let raw = Array(bytes)
        guard raw.count == degreeDigits + 6 else { return nil }
        let hemisphere = raw[raw.count - 1]
        guard hemisphere == positive || hemisphere == negative else { return nil }
        guard raw[degreeDigits + 2] == UInt8(ascii: ".") else { return nil }
        func number(_ range: Range<Int>) -> Int? {
            var value = 0
            for index in range {
                let byte = raw[index]
                guard byte >= 48 && byte <= 57 else { return nil }
                value = value * 10 + Int(byte - 48)
            }
            return value
        }
        guard let degrees = number(0..<degreeDigits),
              let minutes = number(degreeDigits..<(degreeDigits + 2)),
              let hundredths = number((degreeDigits + 3)..<(degreeDigits + 5)),
              minutes < 60, hundredths < 100
        else { return nil }
        var value = Double(degrees) + (Double(minutes) + Double(hundredths) / 100.0) / 60.0
        if hemisphere == negative { value = -value }
        return value
    }
}

enum APRSTime {
    static func looksLikeTimestamp(_ bytes: [UInt8], at index: Int) -> Bool {
        guard index + 7 <= bytes.count else { return false }
        for offset in 0..<6 where bytes[index + offset] < 48 || bytes[index + offset] > 57 {
            return false
        }
        let suffix = bytes[index + 6]
        return suffix == UInt8(ascii: "z") || suffix == UInt8(ascii: "h") || suffix == UInt8(ascii: "/")
    }

    static func parse(_ bytes: [UInt8], now: Date) -> Date? {
        guard bytes.count == 7 else { return nil }
        let digits = bytes.prefix(6).map { Int($0 - 48) }
        guard digits.count == 6, digits.allSatisfy({ (0...9).contains($0) }) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var parts = calendar.dateComponents([.year, .month, .day], from: now)
        let suffix = bytes[6]
        if suffix == UInt8(ascii: "h") {
            parts.hour = digits[0] * 10 + digits[1]
            parts.minute = digits[2] * 10 + digits[3]
            parts.second = digits[4] * 10 + digits[5]
            return calendar.date(from: parts)
        }
        guard suffix == UInt8(ascii: "z") || suffix == UInt8(ascii: "/") else { return nil }
        let day = digits[0] * 10 + digits[1]
        guard (1...31).contains(day) else { return nil }
        parts.day = day
        parts.hour = digits[2] * 10 + digits[3]
        parts.minute = digits[4] * 10 + digits[5]
        parts.second = 0
        guard var date = calendar.date(from: parts) else { return nil }
        if date.timeIntervalSince(now) > 2 * 86_400, let month = parts.month {
            parts.month = month - 1
            date = calendar.date(from: parts) ?? date
        }
        return date
    }

    static func formatDHM(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.day, .hour, .minute], from: date)
        return String(format: "%02d%02d%02dz", parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0)
    }
}

enum Base91 {
    static func decode<S: Sequence>(_ bytes: S) -> Int? where S.Element == UInt8 {
        var value = 0
        var count = 0
        for byte in bytes {
            let digit = Int(byte) - 33
            guard (0..<91).contains(digit) else { return nil }
            value = value * 91 + digit
            count += 1
        }
        return count == 0 ? nil : value
    }

    static func encode(_ value: Int, width: Int) -> [UInt8]? {
        guard value >= 0, width > 0 else { return nil }
        var remainder = value
        var chars = [UInt8](repeating: 33, count: width)
        for index in stride(from: width - 1, through: 0, by: -1) {
            chars[index] = UInt8(33 + (remainder % 91))
            remainder /= 91
        }
        guard remainder == 0 else { return nil }
        return chars
    }
}

enum CompressedMotion {
    struct Motion {
        var courseDegrees: Double?
        var speedKnots: Double?
        var altitudeFeet: Double?
    }

    static func decode(courseByte: UInt8, speedByte: UInt8, typeByte: UInt8) -> Motion {
        let type = Int(typeByte) - 33
        let course = Int(courseByte) - 33
        let speed = Int(speedByte) - 33
        guard type >= 0, (0..<91).contains(course), (0..<91).contains(speed) else { return Motion() }
        switch type & 0x18 {
        case 0x10:
            return Motion(courseDegrees: Double(course * 4), speedKnots: pow(1.08, speed) - 1, altitudeFeet: nil)
        case 0x18:
            return Motion(courseDegrees: nil, speedKnots: nil, altitudeFeet: pow(1.002, course * 91 + speed))
        default:
            return Motion()
        }
    }

    static func encodePosition(
        latitude: Double,
        longitude: Double,
        symbolTable: Character,
        symbol: Character,
        courseDegrees: Double?,
        speedKnots: Double?
    ) -> String? {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        let latN = Int(((90.0 - latitude) * 380926.0).rounded())
        var lon = longitude
        if lon < -180 { lon += 360 }
        if lon > 180 { lon -= 360 }
        let lonN = Int(((lon + 180.0) * 190463.0).rounded())
        guard let latBytes = Base91.encode(max(0, latN), width: 4),
              let lonBytes = Base91.encode(max(0, lonN), width: 4),
              let table = symbolTable.asciiValue, let code = symbol.asciiValue
        else { return nil }
        var courseCode = 0
        var speedCode = 0
        var type = 0x10
        if let courseDegrees {
            courseCode = min(89, max(0, Int((courseDegrees / 4.0).rounded())))
        }
        if let speedKnots, speedKnots > 0 {
            var probe = 0.0
            var steps = 0
            while steps < 90 && probe < speedKnots {
                steps += 1
                probe = pow(1.08, steps) - 1
            }
            speedCode = steps
        }
        if courseDegrees == nil && speedKnots == nil {
            type = 0
            courseCode = 0
            speedCode = 0
        }
        var bytes: [UInt8] = [table]
        bytes.append(contentsOf: latBytes)
        bytes.append(contentsOf: lonBytes)
        bytes.append(code)
        bytes.append(UInt8(33 + courseCode))
        bytes.append(UInt8(33 + speedCode))
        bytes.append(UInt8(33 + type))
        return String(bytes: bytes, encoding: .ascii)
    }

    private static func pow(_ base: Double, _ exponent: Int) -> Double {
        var value = 1.0
        for _ in 0..<max(0, exponent) { value *= base }
        return value
    }
}

private extension UInt8 {
    var isASCIIDigit: Bool { self >= 48 && self <= 57 }
}
