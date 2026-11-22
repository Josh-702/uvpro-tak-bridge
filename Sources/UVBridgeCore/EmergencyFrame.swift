// Copyright 2026 Josh Howard
// SPDX-License-Identifier: Apache-2.0

import Crypto
import Foundation

/// AES-256-GCM over the AX.25 information field only.
/// The address header, including the source callsign, is not an input.
public struct TeamKey: Equatable {
    public var id: Data
    public var bytes: Data

    public init(bytes: Data) {
        self.bytes = bytes
        self.id = Data(SHA256.hash(data: bytes).prefix(4))
    }

    public static func generate() -> TeamKey {
        TeamKey(bytes: SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) })
    }

    public var shareText: String {
        "UVBKEY1.\(id.base64EncodedString()).\(bytes.base64EncodedString())"
    }

    public static func parseShareText(_ text: String) -> TeamKey? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".")
        guard parts.count == 3, parts[0] == "UVBKEY1",
              let id = Data(base64Encoded: String(parts[1])),
              let bytes = Data(base64Encoded: String(parts[2])),
              bytes.count == 32
        else { return nil }
        let key = TeamKey(bytes: bytes)
        guard key.id == id else { return nil }
        return key
    }
}

public enum EmergencyFrame {
    public static let magic = Data("UVB1".utf8)

    public static func isSealed(_ info: Data) -> Bool {
        info.starts(with: magic)
    }

    /// Team mode is the only mode that may seal a payload.
    public static func seal(plaintext: Data, key: TeamKey, mode: OperatingMode, enabled: Bool) -> Data? {
        guard mode == .team, enabled, key.bytes.count == 32 else { return nil }
        do {
            let sealed = try AES.GCM.seal(plaintext, using: SymmetricKey(data: key.bytes))
            guard let combined = sealed.combined else { return nil }
            return magic + key.id + combined
        } catch {
            return nil
        }
    }

    public static func open(sealed: Data, keys: [TeamKey]) -> Data? {
        guard sealed.starts(with: magic), sealed.count > magic.count + 4 + 12 + 16 else { return nil }
        let id = sealed.subdata(in: magic.count..<(magic.count + 4))
        let combined = sealed.subdata(in: (magic.count + 4)..<sealed.count)
        guard let key = keys.first(where: { $0.id == id }) ?? keys.first else { return nil }
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            return try AES.GCM.open(box, using: SymmetricKey(data: key.bytes))
        } catch {
            return nil
        }
    }
}
