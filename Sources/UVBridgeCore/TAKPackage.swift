// Copyright 2026 Josh Howard
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum TAKTransport: String, Codable, Equatable {
    case tcp
    case tls

    public var connectToken: String { self == .tcp ? "tcp" : "ssl" }
}

/// The only server entry iTAK should ever have for this bridge.
/// It does not change between offline and online.
public struct LocalTAKEndpoint: Codable, Equatable {
    public var host: String
    public var port: Int
    public var transport: TAKTransport
    public var displayName: String

    public static let defaultPort = 17747

    public init(
        host: String = "127.0.0.1",
        port: Int = LocalTAKEndpoint.defaultPort,
        transport: TAKTransport = .tcp,
        displayName: String = UVBridgeCore.name
    ) {
        self.host = host
        self.port = port
        self.transport = transport
        self.displayName = displayName
    }

    public var connectString: String { "\(host):\(port):\(transport.connectToken)" }
}

public enum DataPackageBuilder {
    /// A mission package whose only stream is the on-phone endpoint.
    /// Upstream TAK servers are intentionally not an input.
    public static func iTAKPackage(endpoint: LocalTAKEndpoint = LocalTAKEndpoint()) -> Data {
        let uid = "openuvbridge-local-endpoint"
        let manifest = """
        <?xml version="1.0" encoding="UTF-8"?>
        <MissionPackageManifest version="2">
          <Configuration>
            <Parameter name="uid" value="\(xmlEscape(uid))"/>
            <Parameter name="name" value="\(xmlEscape(endpoint.displayName))"/>
            <Parameter name="onReceiveDelete" value="true"/>
          </Configuration>
          <Contents>
            <Content ignore="false" zipEntry="prefs/cot_streams.pref"/>
            <Content ignore="false" zipEntry="readme.txt"/>
          </Contents>
        </MissionPackageManifest>
        """
        let preferences = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <preferences>
          <preference version="1" name="cot_streams">
            <entry key="count" class="class java.lang.Integer">1</entry>
            <entry key="description0" class="class java.lang.String">\(xmlEscape(endpoint.displayName))</entry>
            <entry key="enabled0" class="class java.lang.Boolean">true</entry>
            <entry key="connectString0" class="class java.lang.String">\(xmlEscape(endpoint.connectString))</entry>
            <entry key="useAuth0" class="class java.lang.Boolean">false</entry>
          </preference>
        </preferences>
        """
        let readme = """
        \(endpoint.displayName)

        Import this package into iTAK once. It adds a single server:

            \(endpoint.connectString)

        Leave that entry in place. Open UV Bridge is the server iTAK talks to,
        on this phone, with or without cell service and with or without your
        own TAK server. Do not point iTAK at your upstream server directly.
        The bridge does that itself when the server is reachable, and it
        queues when it is not.

        On a BTECH UV-PRO, Vero VR-N76, or Radioddity GA-5WB:
        Menu > General Settings > KISS TNC > On.
        Quit the radio's own app before connecting. The Bluetooth link is exclusive.
        """
        return ZipArchive.archive([
            "MANIFEST/manifest.xml": Data(manifest.utf8),
            "prefs/cot_streams.pref": Data(preferences.utf8),
            "readme.txt": Data(readme.utf8),
        ])
    }
}

public struct ImportedTAKServer: Equatable {
    public var host: String
    public var port: Int
    public var transport: TAKTransport
    public var clientCertificate: Data?
    public var trustStore: Data?
    /// Password from the package for the truststore, when the pref had one.
    public var trustStorePassword: String?
    /// Password from the package for the client certificate, when the pref had one.
    public var clientPassword: String?

    /// Truststore password, or the ATAK package default when the pref omitted it.
    public var resolvedTrustStorePassword: String {
        trustStorePassword ?? TAKPackageImport.defaultCertificatePassword
    }

    /// Client password, then the truststore password, then the ATAK package default.
    public var resolvedClientPassword: String {
        clientPassword ?? trustStorePassword ?? TAKPackageImport.defaultCertificatePassword
    }

    public var redactedDescription: String {
        let trust = trustStore == nil ? "no truststore" : "truststore present"
        let client = clientCertificate == nil ? "no client certificate" : "client certificate present"
        return "\(host):\(port) \(transport.rawValue), \(client), \(trust), password redacted"
    }
}

public enum TAKPackageImport {
    /// Password ATAK writes into a data package when the operator does not choose one.
    public static let defaultCertificatePassword = "atakatak"

    public static func load(_ data: Data) throws -> ImportedTAKServer {
        let files = try ZipArchive.extract(data)
        var texts: [String] = []
        var certificates: [(name: String, data: Data)] = []
        for (name, payload) in files {
            let lower = name.lowercased()
            if lower.hasSuffix(".p12") || lower.hasSuffix(".pfx") {
                certificates.append((name, payload))
            } else if let text = String(data: payload, encoding: .utf8) {
                texts.append(text)
            }
        }
        let connects = texts.compactMap(findConnectStrings).flatMap { $0 }
        guard let chosen = connects.first(where: { !$0.host.hasPrefix("127.") && $0.host != "localhost" }) ?? connects.first else {
            throw TAKImportError.noConnectString
        }
        var trust: Data?
        var client: Data?
        let trustPassword = firstPassword(named: ["caPassword0", "caPassword"], in: texts)
        let clientPassword = firstPassword(named: ["clientPassword0", "clientPassword"], in: texts)
        for text in texts {
            if let location = firstEntry(named: "caLocation0", in: text) ?? firstEntry(named: "caLocation", in: text) {
                trust = certificates.first(where: { location.hasSuffix($0.name) || $0.name.hasSuffix(location) })?.data ?? trust
            }
            if let location = firstEntry(named: "certificateLocation0", in: text)
                ?? firstEntry(named: "certificateLocation", in: text)
                ?? firstEntry(named: "clientLocation0", in: text)
                ?? firstEntry(named: "clientLocation", in: text) {
                client = certificates.first(where: { location.hasSuffix($0.name) || $0.name.hasSuffix(location) })?.data ?? client
            }
        }
        if trust == nil {
            trust = certificates.first(where: { $0.name.lowercased().contains("trust") || $0.name.lowercased().contains("ca") })?.data
        }
        if client == nil {
            client = certificates.first(where: { $0.data != trust })?.data
        }
        return ImportedTAKServer(
            host: chosen.host,
            port: chosen.port,
            transport: chosen.transport,
            clientCertificate: client,
            trustStore: trust,
            trustStorePassword: trustPassword,
            clientPassword: clientPassword
        )
    }

    private static func firstPassword(named keys: [String], in texts: [String]) -> String? {
        for text in texts {
            for key in keys {
                if let found = firstEntry(named: key, in: text) {
                    return found
                }
            }
        }
        return nil
    }

    private static func findConnectStrings(in text: String) -> [(host: String, port: Int, transport: TAKTransport)] {
        let scalars = Array(text)
        var found: [(String, Int, TAKTransport)] = []
        var index = 0
        while index < scalars.count {
            if scalars[index] == ":" {
                let token = readToken(scalars, endingAt: index)
                let after = readToken(scalars, startingAt: scalars.index(after: index))
                if let port = Int(after.port), let transport = transportToken(after.token), !token.isEmpty {
                    found.append((token, port, transport))
                }
            }
            index += 1
        }
        // The scanner above is too loose (it treats ":8089" without a following protocol).
        // Prefer the explicit host:port:protocol form.
        return explicitConnectStrings(in: text)
    }

    private static func explicitConnectStrings(in text: String) -> [(host: String, port: Int, transport: TAKTransport)] {
        var results: [(String, Int, TAKTransport)] = []
        let parts = text.split { !$0.isLetter && !$0.isNumber && $0 != "." && $0 != "-" && $0 != "_" && $0 != ":" }
        for part in parts {
            let pieces = part.split(separator: ":")
            guard pieces.count == 3, let port = Int(pieces[1]), let transport = transportToken(String(pieces[2])) else {
                continue
            }
            let host = String(pieces[0])
            guard !host.isEmpty, !host.contains("@") else { continue }
            results.append((host, port, transport))
        }
        return results
    }

    private static func transportToken(_ token: String) -> TAKTransport? {
        switch token.lowercased() {
        case "tcp": return .tcp
        case "ssl", "tls": return .tls
        default: return nil
        }
    }

    private static func firstEntry(named key: String, in text: String) -> String? {
        guard let keyRange = text.range(of: "key=\"\(key)\"") ?? text.range(of: "key='\(key)'") else {
            return nil
        }
        let tail = text[keyRange.upperBound...]
        guard let valueRange = tail.range(of: ">") else { return nil }
        let after = tail[valueRange.upperBound...]
        guard let end = after.firstIndex(of: "<") else { return nil }
        let value = after[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : String(value)
    }

    private static func readToken(_ scalars: [Character], endingAt index: Int) -> String { "" }
    private static func readToken(_ scalars: [Character], startingAt index: Int) -> (token: String, port: String) { ("", "") }
}

public enum TAKImportError: Error, Equatable {
    case noConnectString
}

public enum TAKEnrollment {
    public static let defaultPort = 8446

    /// Marti client-certificate enrollment. Host is always the operator's.
    /// Nothing in this function supplies a default server.
    public static func signClientV2URL(host: String, port: Int = TAKEnrollment.defaultPort, clientUID: String) -> URL? {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !trimmed.contains("@"), !trimmed.contains("/"), !trimmed.contains(" "), !trimmed.contains(":") else {
            return nil
        }
        guard !clientUID.isEmpty, !clientUID.contains(" ") else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = trimmed
        components.port = port
        components.path = "/Marti/api/tls/signClient/v2"
        components.queryItems = [
            URLQueryItem(name: "clientUid", value: clientUID),
            URLQueryItem(name: "version", value: "openuvbridge-\(UVBridgeCore.version)"),
        ]
        return components.url
    }

    /// POST body for signClient/v2: PEM armor removed, remaining base64 text, not decoded.
    public static func csrWireBody(pem: String) -> Data? {
        let lines = pem.split(whereSeparator: \.isNewline).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        let body = lines.filter { !$0.hasPrefix("-----") && !$0.isEmpty }.joined()
        guard !body.isEmpty else { return nil }
        return Data(body.utf8)
    }

    public static func certificatePEM(from response: Data) -> String? {
        guard var text = String(data: response, encoding: .utf8) else { return nil }
        if text.contains("BEGIN CERTIFICATE") { return text }
        let collapsed = text.filter { !$0.isWhitespace }
        guard !collapsed.isEmpty, collapsed.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "/" || $0 == "=" }) else {
            return nil
        }
        text = "-----BEGIN CERTIFICATE-----\n\(collapsed)\n-----END CERTIFICATE-----\n"
        return text
    }
}
