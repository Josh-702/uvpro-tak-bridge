// Copyright 2026 Josh Howard
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum ZipError: Error, Equatable {
    case truncated
    case corrupt
    case unsupportedMethod(Int)
    case tooLarge
}

public enum ZipArchive {
    /// STORE-method archive. Entries are written in sorted path order.
    public static func archive(_ files: [String: Data], modified: Date = Date()) -> Data {
        let names = files.keys.sorted()
        var locals: [Data] = []
        var central: [Data] = []
        var offset = 0
        let stamp = dosStamp(modified)
        for name in names {
            let payload = files[name] ?? Data()
            let nameData = Data(name.utf8)
            let crc = CRC32.hash(payload)
            var local = Data()
            local.appendU32(0x04034B50)
            local.appendU16(20)
            local.appendU16(0)
            local.appendU16(0)
            local.appendU16(stamp.time)
            local.appendU16(stamp.date)
            local.appendU32(crc)
            local.appendU32(UInt32(payload.count))
            local.appendU32(UInt32(payload.count))
            local.appendU16(UInt16(nameData.count))
            local.appendU16(0)
            local.append(nameData)
            local.append(payload)
            var directory = Data()
            directory.appendU32(0x02014B50)
            directory.appendU16(20)
            directory.appendU16(20)
            directory.appendU16(0)
            directory.appendU16(0)
            directory.appendU16(stamp.time)
            directory.appendU16(stamp.date)
            directory.appendU32(crc)
            directory.appendU32(UInt32(payload.count))
            directory.appendU32(UInt32(payload.count))
            directory.appendU16(UInt16(nameData.count))
            directory.appendU16(0)
            directory.appendU16(0)
            directory.appendU16(0)
            directory.appendU16(0)
            directory.appendU32(0)
            directory.appendU32(UInt32(offset))
            directory.append(nameData)
            offset += local.count
            locals.append(local)
            central.append(directory)
        }
        var archive = Data()
        for local in locals { archive.append(local) }
        let directoryOffset = archive.count
        var directorySize = 0
        for entry in central {
            archive.append(entry)
            directorySize += entry.count
        }
        archive.appendU32(0x06054B50)
        archive.appendU16(0)
        archive.appendU16(0)
        archive.appendU16(UInt16(names.count))
        archive.appendU16(UInt16(names.count))
        archive.appendU32(UInt32(directorySize))
        archive.appendU32(UInt32(directoryOffset))
        archive.appendU16(0)
        return archive
    }

    public static func extract(_ data: Data) throws -> [String: Data] {
        let bytes = [UInt8](data)
        var index = 0
        var files: [String: Data] = [:]
        while index + 4 <= bytes.count {
            let signature = readU32(bytes, index)
            if signature == 0x02014B50 || signature == 0x06054B50 { break }
            guard signature == 0x04034B50, index + 30 <= bytes.count else { throw ZipError.corrupt }
            let method = Int(readU16(bytes, index + 8))
            let compressedSize = Int(readU32(bytes, index + 18))
            let uncompressedSize = Int(readU32(bytes, index + 22))
            let nameLength = Int(readU16(bytes, index + 26))
            let extraLength = Int(readU16(bytes, index + 28))
            let nameStart = index + 30
            let dataStart = nameStart + nameLength + extraLength
            guard nameStart + nameLength <= bytes.count, dataStart + compressedSize <= bytes.count else {
                throw ZipError.truncated
            }
            let name = String(bytes: bytes[nameStart..<(nameStart + nameLength)], encoding: .utf8) ?? "unknown"
            let payload = Data(bytes[dataStart..<(dataStart + compressedSize)])
            let file: Data
            switch method {
            case 0:
                file = payload
            case 8:
                file = try Inflate.raw(payload, expectedSize: uncompressedSize)
            default:
                throw ZipError.unsupportedMethod(method)
            }
            files[name] = file
            index = dataStart + compressedSize
        }
        return files
    }
}

enum Inflate {
    static func raw(_ data: Data, expectedSize: Int) throws -> Data {
        guard expectedSize >= 0, expectedSize <= 8_000_000 else { throw ZipError.tooLarge }
        var reader = BitReader(bytes: [UInt8](data))
        var output: [UInt8] = []
        output.reserveCapacity(expectedSize)
        var final = false
        while !final {
            final = try reader.readBit() == 1
            let kind = try reader.bits(2)
            switch kind {
            case 0:
                try stored(reader: &reader, output: &output, cap: expectedSize)
            case 1:
                try codes(
                    reader: &reader,
                    output: &output,
                    literal: Tree(lengths: fixedLiteralLengths()),
                    distance: Tree(lengths: fixedDistanceLengths()),
                    cap: expectedSize
                )
            case 2:
                let trees = try dynamicTrees(reader: &reader)
                try codes(reader: &reader, output: &output, literal: trees.literal, distance: trees.distance, cap: expectedSize)
            default:
                throw ZipError.corrupt
            }
        }
        guard output.count == expectedSize else { throw ZipError.corrupt }
        return Data(output)
    }

    private static func stored(reader: inout BitReader, output: inout [UInt8], cap: Int) throws {
        reader.align()
        let length = try reader.u16()
        let complement = try reader.u16()
        guard length ^ 0xFFFF == complement else { throw ZipError.corrupt }
        guard output.count + length <= cap else { throw ZipError.tooLarge }
        for _ in 0..<length {
            output.append(try reader.byte())
        }
    }

    private static func codes(
        reader: inout BitReader,
        output: inout [UInt8],
        literal: Tree,
        distance: Tree,
        cap: Int
    ) throws {
        while true {
            let symbol = try literal.decode(&reader)
            if symbol < 256 {
                guard output.count < cap else { throw ZipError.tooLarge }
                output.append(UInt8(symbol))
            } else if symbol == 256 {
                return
            } else {
                let index = symbol - 257
                guard lengthBase.indices.contains(index) else { throw ZipError.corrupt }
                let length = lengthBase[index] + (try reader.bits(lengthExtra[index]))
                let distSymbol = try distance.decode(&reader)
                guard distBase.indices.contains(distSymbol) else { throw ZipError.corrupt }
                let dist = distBase[distSymbol] + (try reader.bits(distExtra[distSymbol]))
                guard dist > 0, dist <= output.count else { throw ZipError.corrupt }
                guard output.count + length <= cap else { throw ZipError.tooLarge }
                for _ in 0..<length {
                    output.append(output[output.count - dist])
                }
            }
        }
    }

    private static func dynamicTrees(reader: inout BitReader) throws -> (literal: Tree, distance: Tree) {
        let literalCount = try reader.bits(5) + 257
        let distanceCount = try reader.bits(5) + 1
        let codeCount = try reader.bits(4) + 4
        guard literalCount <= 286, distanceCount <= 32, codeCount <= 19 else { throw ZipError.corrupt }
        var codeLengths = [Int](repeating: 0, count: 19)
        for index in 0..<codeCount {
            codeLengths[codeLengthOrder[index]] = try reader.bits(3)
        }
        let codeTree = Tree(lengths: codeLengths)
        var lengths: [Int] = []
        lengths.reserveCapacity(literalCount + distanceCount)
        while lengths.count < literalCount + distanceCount {
            let symbol = try codeTree.decode(&reader)
            if symbol < 16 {
                lengths.append(symbol)
            } else if symbol == 16 {
                guard let previous = lengths.last else { throw ZipError.corrupt }
                let times = 3 + (try reader.bits(2))
                lengths.append(contentsOf: Array(repeating: previous, count: times))
            } else if symbol == 17 {
                lengths.append(contentsOf: Array(repeating: 0, count: 3 + (try reader.bits(3))))
            } else if symbol == 18 {
                lengths.append(contentsOf: Array(repeating: 0, count: 11 + (try reader.bits(7))))
            } else {
                throw ZipError.corrupt
            }
        }
        guard lengths.count == literalCount + distanceCount else { throw ZipError.corrupt }
        return (
            Tree(lengths: Array(lengths.prefix(literalCount))),
            Tree(lengths: Array(lengths.suffix(distanceCount)))
        )
    }

    private static func fixedLiteralLengths() -> [Int] {
        var lengths = [Int](repeating: 0, count: 288)
        for index in 0...143 { lengths[index] = 8 }
        for index in 144...255 { lengths[index] = 9 }
        for index in 256...279 { lengths[index] = 7 }
        for index in 280...287 { lengths[index] = 8 }
        return lengths
    }

    private static func fixedDistanceLengths() -> [Int] {
        Array(repeating: 5, count: 32)
    }

    private static let codeLengthOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
    private static let lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    private static let lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    private static let distBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
    private static let distExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
}

private struct BitReader {
    var bytes: [UInt8]
    var index = 0
    var bit = 0

    mutating func readBit() throws -> Int {
        guard index < bytes.count else { throw ZipError.truncated }
        let value = Int((bytes[index] >> bit) & 1)
        bit += 1
        if bit == 8 {
            bit = 0
            index += 1
        }
        return value
    }

    mutating func bits(_ count: Int) throws -> Int {
        var value = 0
        for shift in 0..<count {
            value |= try readBit() << shift
        }
        return value
    }

    mutating func align() {
        if bit != 0 {
            bit = 0
            index += 1
        }
    }

    mutating func byte() throws -> UInt8 {
        align()
        guard index < bytes.count else { throw ZipError.truncated }
        let value = bytes[index]
        index += 1
        return value
    }

    mutating func u16() throws -> Int {
        let low = Int(try byte())
        let high = Int(try byte())
        return low | (high << 8)
    }
}

private struct HuffTree {
    var left: [Int]
    var right: [Int]
    var symbol: [Int]

    init(lengths: [Int]) {
        var left: [Int] = [-1]
        var right: [Int] = [-1]
        var symbol: [Int] = [-1]
        let maxBits = max(lengths.max() ?? 0, 0)
        var counts = [Int](repeating: 0, count: maxBits + 1)
        for length in lengths where length > 0 { counts[length] += 1 }
        var next = [Int](repeating: 0, count: maxBits + 1)
        var code = 0
        counts[0] = 0
        if maxBits >= 1 {
            for bits in 1...maxBits {
                code = (code + counts[bits - 1]) << 1
                next[bits] = code
            }
        }
        func appendNode() -> Int {
            left.append(-1)
            right.append(-1)
            symbol.append(-1)
            return left.count - 1
        }
        for (value, length) in lengths.enumerated() where length > 0 {
            var node = 0
            let assigned = next[length]
            next[length] = assigned + 1
            for shift in stride(from: length - 1, through: 0, by: -1) {
                let bit = (assigned >> shift) & 1
                if bit == 0 {
                    if left[node] < 0 {
                        let created = appendNode()
                        left[node] = created
                    }
                    node = left[node]
                } else {
                    if right[node] < 0 {
                        let created = appendNode()
                        right[node] = created
                    }
                    node = right[node]
                }
            }
            symbol[node] = value
        }
        self.left = left
        self.right = right
        self.symbol = symbol
    }

    func decode(_ reader: inout BitReader) throws -> Int {
        var node = 0
        while symbol[node] < 0 {
            let bit = try reader.readBit()
            let next = bit == 0 ? left[node] : right[node]
            guard next >= 0 else { throw ZipError.corrupt }
            node = next
        }
        return symbol[node]
    }
}

private typealias Tree = HuffTree

private enum CRC32 {
    static let table: [UInt32] = {
        (0..<256).map { index in
            var crc = UInt32(index)
            for _ in 0..<8 {
                crc = (crc & 1) == 1 ? (0xEDB88320 ^ (crc >> 1)) : (crc >> 1)
            }
            return crc
        }
    }()

    static func hash(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private func dosStamp(_ date: Date) -> (time: UInt16, date: UInt16) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    let year = max(0, (parts.year ?? 1980) - 1980)
    let month = parts.month ?? 1
    let day = parts.day ?? 1
    let hour = parts.hour ?? 0
    let minute = parts.minute ?? 0
    let second = (parts.second ?? 0) / 2
    let dosDate = UInt16((year << 9) | (month << 5) | day)
    let dosTime = UInt16((hour << 11) | (minute << 5) | second)
    return (dosTime, dosDate)
}

private extension Data {
    mutating func appendU16(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendU32(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}

private func readU16(_ bytes: [UInt8], _ index: Int) -> UInt16 {
    UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8)
}

private func readU32(_ bytes: [UInt8], _ index: Int) -> UInt32 {
    UInt32(bytes[index])
        | (UInt32(bytes[index + 1]) << 8)
        | (UInt32(bytes[index + 2]) << 16)
        | (UInt32(bytes[index + 3]) << 24)
}
