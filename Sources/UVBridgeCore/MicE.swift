// Copyright 2026 Josh Howard
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Mic-E, from APRS Protocol Reference 1.0.1 chapter 10.
/// Latitude and the message/hemisphere bits live in the AX.25 destination.
/// Longitude, course, speed, and symbol live in the information field.
/// Kenwood radios swapped the `'` / `` ` `` current-fix bytes; both are accepted.
public enum MicE {
    public struct Header: Equatable {
        public var latitude: Double
        public var bits: [Bool]
        public var custom: Bool
        public var longitudeOffset100: Bool
        public var west: Bool
        public var message: String
    }

    public static func parse(info: [UInt8], destination: AX25Address) -> APRSPosition? {
        guard info.count >= 8, isType(info[0]), let header = decodeDestination(destination.call) else {
            return nil
        }
        guard let longitude = decodeLongitude(
            degrees: info[1],
            minutes: info[2],
            hundredths: info[3],
            offset100: header.longitudeOffset100,
            west: header.west
        ) else { return nil }
        let motion = decodeCourseSpeed(sp: info[4], dc: info[5], se: info[6])
        let symbol = info[7]
        var commentStart = 8
        var table: UInt8 = UInt8(ascii: "/")
        if info.count >= 9 {
            table = info[8]
            commentStart = 9
        }
        var comment = Array(info.dropFirst(commentStart))
        var altitude: Double?
        if comment.count >= 4, comment[3] == UInt8(ascii: "}"),
           let value = Base91.decode(comment[0..<3]) {
            altitude = Double(value - 10_000)
            comment = Array(comment.dropFirst(4))
        }
        return APRSPosition(
            latitude: header.latitude,
            longitude: longitude,
            symbolTable: APRSASCII.symbol(table),
            symbol: APRSASCII.symbol(symbol),
            comment: APRSASCII.string(comment),
            courseDegrees: motion.course,
            speedKnots: motion.speed,
            altitudeMeters: altitude,
            messaging: true,
            micE: true,
            micEMessage: header.message
        )
    }

    public static func isEmergency(bits: [Bool], custom: Bool) -> Bool {
        bits.count == 3 && bits.allSatisfy { $0 == false } && !custom
    }

    /// Builds a Mic-E destination and information field. Refuses the emergency bit pattern.
    public static func encode(
        latitude: Double,
        longitude: Double,
        symbolTable: Character = "/",
        symbol: Character = ">",
        comment: String = "",
        courseDegrees: Double = 0,
        speedKnots: Double = 0,
        bits: [Bool] = [true, true, true],
        custom: Bool = false
    ) -> (destination: String, info: Data)? {
        guard bits.count == 3, !isEmergency(bits: bits, custom: custom) else { return nil }
        guard let longitudeBytes = encodeLongitude(longitude),
              let destination = encodeDestination(
                latitude: latitude,
                bits: bits,
                custom: custom,
                offset100: longitudeBytes.offset100,
                west: longitudeBytes.west
              ),
              let table = symbolTable.asciiValue,
              let code = symbol.asciiValue
        else { return nil }
        var info: [UInt8] = [UInt8(ascii: "`")]
        info.append(longitudeBytes.degrees)
        info.append(longitudeBytes.minutes)
        info.append(longitudeBytes.hundredths)
        info.append(contentsOf: encodeCourseSpeed(course: courseDegrees, speed: speedKnots))
        info.append(code)
        info.append(table)
        info.append(contentsOf: APRSASCII.asciiOnly(comment).utf8)
        return (destination, Data(info))
    }

    public static func decodeDestination(_ call: String) -> Header? {
        let bytes = Array(call.uppercased().utf8)
        guard bytes.count == 6 else { return nil }
        var digits: [Int] = []
        var flags: [Bool] = []
        var customFlags: [Bool] = []
        for byte in bytes {
            guard let part = decodeCharacter(byte) else { return nil }
            digits.append(part.digit)
            flags.append(part.flag)
            customFlags.append(part.custom)
        }
        let degrees = digits[0] * 10 + digits[1]
        let minutes = digits[2] * 10 + digits[3]
        let hundredths = digits[4] * 10 + digits[5]
        guard degrees <= 90, minutes < 60, hundredths < 100 else { return nil }
        var latitude = Double(degrees) + (Double(minutes) + Double(hundredths) / 100.0) / 60.0
        if !flags[3] { latitude = -latitude }
        let bits = [flags[0], flags[1], flags[2]]
        let custom = customFlags[0] || customFlags[1] || customFlags[2]
        return Header(
            latitude: latitude,
            bits: bits,
            custom: custom,
            longitudeOffset100: flags[4],
            west: flags[5],
            message: messageLabel(bits: bits, custom: custom)
        )
    }

    public static func decodeLongitude(degrees: UInt8, minutes: UInt8, hundredths: UInt8, offset100: Bool, west: Bool) -> Double? {
        var degree = Int(degrees) - 28
        if (180...189).contains(degree) {
            degree -= 80
        } else if (190...199).contains(degree) {
            degree -= 190
        }
        if offset100 { degree += 100 }
        var minute = Int(minutes) - 28
        if minute >= 60 { minute -= 60 }
        let frac = Int(hundredths) - 28
        guard (0...179).contains(degree), (0...59).contains(minute), (0...99).contains(frac) else { return nil }
        var longitude = Double(degree) + (Double(minute) + Double(frac) / 100.0) / 60.0
        if west { longitude = -longitude }
        return longitude
    }

    public static func decodeCourseSpeed(sp: UInt8, dc: UInt8, se: UInt8) -> (course: Double, speed: Double) {
        let speedTens = Int(sp) - 28
        let dcValue = Int(dc) - 28
        let seValue = Int(se) - 28
        var speed = speedTens * 10 + dcValue / 10
        var course = (dcValue % 10) * 100 + seValue
        if speed >= 800 { speed -= 800 }
        if course >= 400 { course -= 400 }
        return (Double(course), Double(speed))
    }

    static func messageLabel(bits: [Bool], custom: Bool) -> String {
        let value = (bits[0] ? 4 : 0) + (bits[1] ? 2 : 0) + (bits[2] ? 1 : 0)
        let standard = ["Emergency", "Priority", "Special", "Committed", "Returning", "In Service", "En Route", "Off Duty"]
        let customNames = ["Emergency", "Custom-1", "Custom-2", "Custom-3", "Custom-4", "Custom-5", "Custom-6", "Custom-7"]
        return (custom ? customNames : standard)[value]
    }

    static func decodeCharacter(_ byte: UInt8) -> (digit: Int, flag: Bool, custom: Bool)? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"):
            return (Int(byte - UInt8(ascii: "0")), false, false)
        case UInt8(ascii: "A")...UInt8(ascii: "J"):
            return (Int(byte - UInt8(ascii: "A")), true, true)
        case UInt8(ascii: "K"):
            return (0, true, true)
        case UInt8(ascii: "L"):
            return (0, false, true)
        case UInt8(ascii: "P")...UInt8(ascii: "Y"):
            return (Int(byte - UInt8(ascii: "P")), true, false)
        case UInt8(ascii: "Z"):
            return (0, true, false)
        default:
            return nil
        }
    }

    static func encodeCharacter(digit: Int, flag: Bool, custom: Bool) -> UInt8? {
        guard (0...9).contains(digit) else { return nil }
        if flag && custom { return UInt8(ascii: "A") + UInt8(digit) }
        if flag && !custom { return UInt8(ascii: "P") + UInt8(digit) }
        return UInt8(ascii: "0") + UInt8(digit)
    }

    static func encodeDestination(
        latitude: Double,
        bits: [Bool],
        custom: Bool,
        offset100: Bool,
        west: Bool
    ) -> String? {
        guard (-90...90).contains(latitude), bits.count == 3 else { return nil }
        let north = latitude >= 0
        var degrees = Int(abs(latitude))
        var hundredths = Int(((abs(latitude) - Double(degrees)) * 6000.0).rounded())
        if hundredths >= 6000 {
            hundredths -= 6000
            degrees += 1
        }
        guard degrees <= 90 else { return nil }
        let minutes = hundredths / 100
        let frac = hundredths % 100
        let digits = [
            degrees / 10, degrees % 10,
            minutes / 10, minutes % 10,
            frac / 10, frac % 10,
        ]
        let flags = [bits[0], bits[1], bits[2], north, offset100, west]
        var bytes: [UInt8] = []
        for index in 0..<6 {
            let useCustom = index < 3 && custom
            guard let byte = encodeCharacter(digit: digits[index], flag: flags[index], custom: useCustom) else {
                return nil
            }
            bytes.append(byte)
        }
        return String(bytes: bytes, encoding: .ascii)
    }

    static func encodeLongitude(_ longitude: Double) -> (degrees: UInt8, minutes: UInt8, hundredths: UInt8, offset100: Bool, west: Bool)? {
        guard (-180...180).contains(longitude) else { return nil }
        let west = longitude < 0
        var degrees = Int(abs(longitude))
        var hundredths = Int(((abs(longitude) - Double(degrees)) * 6000.0).rounded())
        if hundredths >= 6000 {
            hundredths -= 6000
            degrees += 1
        }
        if degrees > 179 { return nil }
        let offset100 = degrees >= 100
        let base = offset100 ? degrees - 100 : degrees
        let minutes = hundredths / 100
        let frac = hundredths % 100
        return (UInt8(base + 28), UInt8(minutes + 28), UInt8(frac + 28), offset100, west)
    }

    static func encodeCourseSpeed(course: Double, speed: Double) -> [UInt8] {
        var courseInt = Int(course.rounded()) % 360
        if courseInt < 0 { courseInt += 360 }
        let speedInt = max(0, min(799, Int(speed.rounded())))
        let tens = speedInt / 10
        let ones = speedInt % 10
        let hundreds = courseInt / 100
        let remainder = courseInt % 100
        let dc = ones * 10 + hundreds
        return [UInt8(tens + 28), UInt8(dc + 28), UInt8(remainder + 28)]
    }

    static func isType(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: "'") || byte == UInt8(ascii: "`") || byte == 0x1C || byte == 0x1D
    }
}
