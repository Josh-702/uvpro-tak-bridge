// Copyright 2026 Josh Howard
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Network
import Security

struct TAKTLSMaterial {
    var identity: SecIdentity
    var anchors: [SecCertificate]
}

enum TAKCredentialStore {
    private static let service = "net.wa7brm.openuvbridge.tak"

    static let clientCertificate = "client-p12"
    static let trustStore = "trust-p12"
    static let clientPassword = "client-password"
    static let trustStorePassword = "trust-password"

    static func save(account: String, data: Data) -> Bool {
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func load(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    static func savePassword(account: String, password: String) -> Bool {
        save(account: account, data: Data(password.utf8))
    }

    static func loadPassword(account: String) -> String? {
        guard let data = load(account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum TAKPKCS12 {
    struct Unlocked {
        var identity: SecIdentity?
        var certificates: [SecCertificate]
    }

    enum ImportFailure: Equatable {
        case wrongPassword
        case unsupportedFormat(OSStatus)
    }

    enum ImportResult {
        case unlocked(Unlocked)
        case failed(ImportFailure)
    }

    /// A wrong password is only `errSecAuthFailed`. RC2-40 stores from `openssl -legacy`
    /// come back as a decode or format error, which is not a password problem.
    static func unlock(_ data: Data, password: String) -> ImportResult {
        let options = [kSecImportExportPassphrase as String: password] as CFDictionary
        var raw: CFArray?
        let status = SecPKCS12Import(data as CFData, options, &raw)
        guard status == errSecSuccess, let items = raw as? [[String: Any]], !items.isEmpty else {
            if status == errSecAuthFailed {
                return .failed(.wrongPassword)
            }
            print("PKCS12 import OSStatus \(status)")
            return .failed(.unsupportedFormat(status))
        }

        var identity: SecIdentity?
        var certificates: [SecCertificate] = []
        for item in items {
            if let found = item[kSecImportItemIdentity as String], CFGetTypeID(found as CFTypeRef) == SecIdentityGetTypeID() {
                identity = found as! SecIdentity
            }
            if let chain = item[kSecImportItemCertChain as String] as? [SecCertificate] {
                certificates.append(contentsOf: chain)
            }
        }
        if certificates.isEmpty, let identity {
            var certificate: SecCertificate?
            if SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate {
                certificates = [certificate]
            }
        }
        guard identity != nil || !certificates.isEmpty else {
            return .failed(.unsupportedFormat(errSecDecode))
        }
        return .unlocked(Unlocked(identity: identity, certificates: certificates))
    }
}

enum TAKTLS {
    static func parameters(host _: String, material: TAKTLSMaterial) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let security = tls.securityProtocolOptions
        sec_protocol_options_set_peer_authentication_required(security, true)
        if let local = sec_identity_create(material.identity) {
            sec_protocol_options_set_local_identity(security, local)
        }
        let anchors = material.anchors
        sec_protocol_options_set_verify_block(security, { _, trust, complete in
            let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
            SecTrustSetAnchorCertificates(secTrust, anchors as CFArray)
            SecTrustSetAnchorCertificatesOnly(secTrust, true)
            complete(SecTrustEvaluateWithError(secTrust, nil))
        }, DispatchQueue(label: "net.wa7brm.openuvbridge.tls"))
        return NWParameters(tls: tls)
    }
}

enum UpstreamLink: Equatable {
    case noServer
    case noCertificate
    case passwordNeeded
    case connecting
    case connected
    case certificateRejected
    case unreachable

    var label: String {
        switch self {
        case .noServer: return "No server"
        case .noCertificate: return "No client certificate"
        case .passwordNeeded: return "Certificate password needed"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .certificateRejected: return "Certificate rejected"
        case .unreachable: return "Unreachable"
        }
    }
}
