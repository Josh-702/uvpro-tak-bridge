// Copyright 2026 Josh Howard
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// KISS TNC framing (AX.25 KISS) plus the BLE GATT UUIDs from the open
/// BLE KISS API. Frames may be split across notifications or concatenated,
/// so the decoder is a byte stream, not a one-shot parser.
///
/// Spec: https://github.com/hessu/aprs-specs/blob/master/BLE-KISS-API.md
public enum BLEKISS {
    public static let serviceUUID = "00000001-BA2A-46C9-AE49-01B0961F68BB"
    public static let transmitCharacteristicUUID = "00000002-BA2A-46C9-AE49-01B0961F68BB"
    public static let receiveCharacteristicUUID = "00000003-BA2A-46C9-AE49-01B0961F68BB"

    /// AX.25 UI max (header + 8 digipeaters + 256 info) and worst-case escaping.
    public static let maximumEncodedFrame = 660
}

public struct KISSFrame: Equatable {
    public var port: UInt8
    public var command: UInt8
    public var payload: Data

    public var isData: Bool { command == 0 }

    public init(port: UInt8 = 0, command: UInt8 = 0, payload: Data) {
        self.port = port & 0x0F
        self.command = command & 0x0F
        self.payload = payload
    }
}

public enum KISS {
    public static let fend: UInt8 = 0xC0
    public static let fesc: UInt8 = 0xDB
    public static let tfend: UInt8 = 0xDC
    public static let tfesc: UInt8 = 0xDD

    public static func encode(_ frame: KISSFrame) -> Data {
        var out: [UInt8] = [fend, (frame.port << 4) | frame.command]
        out.reserveCapacity(frame.payload.count + 3)
        for byte in frame.payload {
            if byte == fend {
                out.append(fesc)
                out.append(tfend)
            } else if byte == fesc {
                out.append(fesc)
                out.append(tfesc)
            } else {
                out.append(byte)
            }
        }
        out.append(fend)
        return Data(out)
    }
}

public final class KISSStreamDecoder {
    private var buffer: [UInt8] = []
    private var inFrame = false
    private var escaped = false

    public init() {}

    public func reset() {
        buffer.removeAll(keepingCapacity: true)
        inFrame = false
        escaped = false
    }

    /// Feed an arbitrary slice from a BLE notification, a serial port, or a test.
    public func append(_ data: Data) -> [KISSFrame] {
        var frames: [KISSFrame] = []
        for byte in data {
            if byte == KISS.fend {
                if inFrame, !buffer.isEmpty {
                    if let frame = Self.frame(from: buffer) {
                        frames.append(frame)
                    }
                }
                buffer.removeAll(keepingCapacity: true)
                inFrame = true
                escaped = false
                continue
            }
            guard inFrame else { continue }
            if escaped {
                if byte == KISS.tfend {
                    buffer.append(KISS.fend)
                } else if byte == KISS.tfesc {
                    buffer.append(KISS.fesc)
                }
                escaped = false
            } else if byte == KISS.fesc {
                escaped = true
            } else {
                buffer.append(byte)
            }
            if buffer.count > BLEKISS.maximumEncodedFrame {
                buffer.removeAll(keepingCapacity: true)
                inFrame = false
                escaped = false
            }
        }
        return frames
    }

    private static func frame(from bytes: [UInt8]) -> KISSFrame? {
        guard let commandByte = bytes.first else { return nil }
        return KISSFrame(
            port: commandByte >> 4,
            command: commandByte & 0x0F,
            payload: Data(bytes.dropFirst())
        )
    }
}
