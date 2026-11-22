// Copyright 2026 Josh Howard
// SPDX-License-Identifier: Apache-2.0

import CoreLocation
import Foundation
import SwiftUI
import UserNotifications
import UVBridgeCore

@MainActor
final class AppModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var modeSummary = OperatorHint.offline
    @Published var modeName = "Offline"
    @Published var stations: [Station] = []
    @Published var packetLog: [PacketLogEntry] = []
    @Published var txLog: [TXLogEntry] = []
    @Published var radioStatus = "Bluetooth is starting"
    @Published var radioHint: String?
    @Published var discovered: [RadioAdvertisement] = []
    @Published var callsign = ""
    @Published var ssid = 0
    @Published var path = ""
    @Published var operatingMode = OperatingMode.team
    @Published var teamChannel = ""
    @Published var rosterEntry = ""
    @Published var emergencyEncryption = false
    @Published var encryptionLog = ""
    @Published var radioPanel = RadioPanel()
    @Published var comment = ""
    @Published var symbol = "["
    @Published var beaconEnabled = true
    @Published var upstreamHost = ""
    @Published var upstreamPort = "8089"
    @Published var upstreamTLS = true
    @Published var mirrorServer = false
    @Published var allowThirdParty = false
    @Published var localConnect = LocalTAKEndpoint().connectString
    @Published var importNote = ""
    @Published var upstreamLink = UpstreamLink.noServer
    @Published var needsCertificatePassword = false
    @Published var certificatePassword = ""
    @Published var refusals: [String] = []

    let engine: BridgeEngine
    private let radio: RadioSession
    private let localServer: LocalTAKService
    private let upstream: UpstreamTAKClient
    private let paths: PathWatcher
    private let location = CLLocationManager()
    private var ticker: Timer?
    private let configURL: URL
    private let snapshotURL: URL

    override init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        configURL = support.appendingPathComponent("bridge-config.json")
        snapshotURL = support.appendingPathComponent("bridge-snapshot.json")
        let restored = (try? Data(contentsOf: configURL)).flatMap { try? JSONDecoder().decode(BridgeConfig.self, from: $0) }
        engine = BridgeEngine(config: restored ?? BridgeConfig())
        radio = RadioSession()
        localServer = LocalTAKService()
        upstream = UpstreamTAKClient()
        paths = PathWatcher()
        super.init()
        pullFromEngine()
        if let snapshot = (try? Data(contentsOf: snapshotURL)).flatMap({ try? JSONDecoder().decode(BridgeSnapshot.self, from: $0) }) {
            engine.restore(snapshot)
            refreshLists()
        }
        radio.owner = self
        localServer.owner = self
        upstream.owner = self
        paths.owner = self
        restoreCertificates()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        location.pausesLocationUpdatesAutomatically = false
        radio.start()
        localServer.start(port: engine.localEndpoint.port)
        paths.start()
        loadTeamKeys()
        UNUserNotificationCenter.current().delegate = self
        location.requestAlwaysAuthorization()
        location.startUpdatingLocation()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func refreshLists() {
        modeSummary = engine.mode.summary
        modeName = String(describing: engine.mode)
        stations = engine.stations
        packetLog = engine.packetLog.reversed()
        txLog = engine.txLog.reversed()
        localConnect = engine.localEndpoint.connectString
    }

    func saveSettings() {
        var config = engine.config
        config.callsign = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        config.ssid = ssid
        config.operatingMode = operatingMode
        config.teamChannelMegahertz = Double(teamChannel)
        config.emergencyEncryption = emergencyEncryption && operatingMode == .team
        config.path = operatingMode == .team ? path : (path.isEmpty ? TeamPolicy.publicDigipeaterPath : path)
        config.comment = comment
        config.symbol = symbol.isEmpty ? "[" : symbol
        config.beaconEnabled = beaconEnabled
        config.mirrorAllServerStations = mirrorServer
        config.part97.allowThirdPartyToRF = allowThirdParty
        let host = upstreamHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.isEmpty {
            config.upstream = nil
        } else {
            config.upstream = UpstreamConfig(
                host: host,
                port: Int(upstreamPort) ?? 8089,
                transport: upstreamTLS ? .tls : .tcp,
                hasClientIdentity: upstream.hasIdentity
            )
        }
        engine.config = config
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: configURL, options: .atomic)
        }
        persistSnapshot()
        refreshLists()
        upstream.reconnectIfNeeded()
    }

    func apply(_ effect: BridgeEffect) {
        localServer.send(effect.localXML)
        upstream.send(effect.upstreamXML)
        for frame in effect.radioFrames {
            radio.write(frame)
        }
        if !effect.refusals.isEmpty {
            refusals = effect.refusals.map { "\($0.reason.rawValue): \($0.detail)" } + refusals
            refusals = Array(refusals.prefix(8))
        }
        refreshLists()
        persistSnapshot()
        upstream.reconnectIfNeeded()
    }

    func tick() {
        apply(engine.tick(now: Date()))
    }

    func connectRadio(_ id: UUID) {
        radio.connect(id)
    }

    func packageFile() -> URL {
        let data = DataPackageBuilder.iTAKPackage(endpoint: engine.localEndpoint)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("OpenUVBridge-iTAK.zip")
        try? data.write(to: url, options: .atomic)
        return url
    }

    func importServerPackage(_ data: Data) {
        do {
            let imported = try TAKPackageImport.load(data)
            upstreamHost = imported.host
            upstreamPort = String(imported.port)
            upstreamTLS = imported.transport == .tls
            forgetCertificateFiles()
            storePackage(imported)
            importNote = imported.redactedDescription
            if !applyStoredCertificates(
                clientPassword: imported.resolvedClientPassword,
                trustPassword: imported.resolvedTrustStorePassword
            ) {
                needsCertificatePassword = true
                upstreamLink = .passwordNeeded
                importNote = "The certificate password was not accepted. Enter the password from the data package."
            } else {
                needsCertificatePassword = false
                certificatePassword = ""
            }
            saveSettings()
        } catch {
            importNote = "That package did not contain a server address."
        }
    }

    func unlockCertificates() {
        let password = certificatePassword
        guard !password.isEmpty else { return }
        if applyStoredCertificates(clientPassword: password, trustPassword: password) {
            needsCertificatePassword = false
            certificatePassword = ""
            importNote = "Certificates unlocked. Password stored in the Keychain."
            saveSettings()
        } else {
            needsCertificatePassword = true
            upstreamLink = .passwordNeeded
            importNote = "That password did not unlock the certificates."
        }
    }

    nonisolated func noteUpstreamLink(_ link: UpstreamLink) {
        MainActor.assumeIsolated {
            self.upstreamLink = link
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            if manager.authorizationStatus == .authorizedAlways {
                manager.allowsBackgroundLocationUpdates = true
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last, fix.horizontalAccuracy >= 0 else { return }
        let speedKnots = fix.speed >= 0 ? fix.speed * 1.94384 : 0
        let course = fix.course >= 0 ? fix.course : nil
        let position = PositionFix(
            latitude: fix.coordinate.latitude,
            longitude: fix.coordinate.longitude,
            courseDegrees: course,
            speedKnots: speedKnots,
            timestamp: fix.timestamp
        )
        MainActor.assumeIsolated {
            self.apply(self.engine.updateOwnPosition(position, now: Date()))
        }
    }

    /// Bluetooth and Network callbacks are scheduled on the main queue, but those
    /// closures are not main-actor isolated. Enter the actor here so the UI update
    /// stays synchronous with the callback that produced it.
    nonisolated func setRadioStatus(_ text: String, hint: String?) {
        MainActor.assumeIsolated {
            self.radioStatus = text
            self.radioHint = hint
        }
    }

    nonisolated func setDiscovered(_ radios: [RadioAdvertisement]) {
        MainActor.assumeIsolated {
            self.discovered = radios
        }
    }

    nonisolated func radioBytes(_ data: Data) {
        MainActor.assumeIsolated {
            self.apply(self.engine.ingestKISS(data, now: Date()))
        }
    }

    nonisolated func radioLink(_ connected: Bool) {
        MainActor.assumeIsolated {
            self.apply(connected ? self.engine.radioDidConnect(now: Date()) : self.engine.radioDidDisconnect(now: Date()))
        }
    }

    nonisolated func localBytes(_ data: Data) {
        MainActor.assumeIsolated {
            self.apply(self.engine.ingestLocalBytes(data, now: Date()))
        }
    }

    nonisolated func localClientCount(_ count: Int) {
        MainActor.assumeIsolated {
            // The service reports transitions one client at a time.
            if count > 0 {
                self.apply(self.engine.localClientDidConnect(now: Date()))
            } else {
                self.apply(self.engine.localClientDidDisconnect(now: Date()))
            }
        }
    }

    nonisolated func pathChanged(_ satisfied: Bool) {
        MainActor.assumeIsolated {
            self.apply(self.engine.setPath(satisfied: satisfied, now: Date()))
        }
    }

    nonisolated func upstreamReady() {
        MainActor.assumeIsolated {
            self.apply(self.engine.noteUpstreamReady(now: Date()))
        }
    }

    nonisolated func upstreamFailed() {
        MainActor.assumeIsolated {
            self.apply(self.engine.noteUpstreamFailed(now: Date()))
        }
    }

    nonisolated func upstreamBytes(_ data: Data) {
        MainActor.assumeIsolated {
            self.apply(self.engine.ingestUpstreamBytes(data, now: Date()))
        }
    }

    private func pullFromEngine() {
        let config = engine.config
        callsign = config.callsign
        ssid = config.ssid
        operatingMode = config.operatingMode
        path = config.path
        teamChannel = config.teamChannelMegahertz.map { String($0) } ?? ""
        emergencyEncryption = config.emergencyEncryption
        comment = config.comment
        symbol = config.symbol
        beaconEnabled = config.beaconEnabled
        mirrorServer = config.mirrorAllServerStations
        allowThirdParty = config.part97.allowThirdPartyToRF
        upstreamHost = config.upstream?.host ?? ""
        upstreamPort = String(config.upstream?.port ?? 8089)
        upstreamTLS = config.upstream?.transport != .tcp
        refreshLists()
    }

    private func restoreCertificates() {
        guard applyStoredCertificates(
            clientPassword: TAKCredentialStore.loadPassword(account: TAKCredentialStore.clientPassword) ?? "",
            trustPassword: TAKCredentialStore.loadPassword(account: TAKCredentialStore.trustStorePassword) ?? ""
        ) else {
            if TAKCredentialStore.load(account: TAKCredentialStore.clientCertificate) != nil {
                needsCertificatePassword = true
                upstreamLink = .passwordNeeded
            }
            return
        }
        needsCertificatePassword = false
    }

    private func storePackage(_ imported: ImportedTAKServer) {
        if let client = imported.clientCertificate {
            _ = TAKCredentialStore.save(account: TAKCredentialStore.clientCertificate, data: client)
        }
        if let trust = imported.trustStore {
            _ = TAKCredentialStore.save(account: TAKCredentialStore.trustStore, data: trust)
        }
    }

    @discardableResult
    private func applyStoredCertificates(clientPassword: String, trustPassword: String) -> Bool {
        let clientData = TAKCredentialStore.load(account: TAKCredentialStore.clientCertificate)
        let trustData = TAKCredentialStore.load(account: TAKCredentialStore.trustStore)
        guard clientData != nil || trustData != nil else {
            upstream.use(nil)
            return true
        }
        guard let clientData else {
            upstream.use(nil)
            return false
        }
        guard let unlockedClient = TAKPKCS12.unlock(clientData, password: clientPassword),
              let identity = unlockedClient.identity
        else {
            upstream.use(nil)
            return false
        }
        _ = TAKCredentialStore.savePassword(account: TAKCredentialStore.clientPassword, password: clientPassword)
        var anchors: [SecCertificate] = []
        if let trustData {
            guard let unlockedTrust = TAKPKCS12.unlock(trustData, password: trustPassword) else {
                upstream.use(nil)
                return false
            }
            anchors = unlockedTrust.certificates
            _ = TAKCredentialStore.savePassword(account: TAKCredentialStore.trustStorePassword, password: trustPassword)
        }
        if anchors.isEmpty {
            var certificate: SecCertificate?
            if SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate {
                anchors = [certificate]
            }
        }
        guard !anchors.isEmpty else {
            upstream.use(nil)
            return false
        }
        upstream.use(TAKTLSMaterial(identity: identity, anchors: anchors))
        return true
    }

    private var settingsBody: Data?
    private var channelBodies: [Int: Data] = [:]
    private var auditURL: URL { configURL.deletingLastPathComponent().appendingPathComponent("encryption-audit.txt") }

    func radioControlReady() {
        radioPanel.control = true
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { _, _ in }
        let next = UNNotificationAction(identifier: "channel.next", title: "Next channel", options: [])
        let previous = UNNotificationAction(identifier: "channel.previous", title: "Previous channel", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "radio.channel", actions: [previous, next], intentIdentifiers: []),
        ])
        let content = UNMutableNotificationContent()
        content.title = "Open UV Bridge"
        content.body = "Use Next channel or Previous channel without leaving iTAK."
        content.categoryIdentifier = "radio.channel"
        center.add(UNNotificationRequest(identifier: "radio.channel", content: content, trigger: nil))
        radio.send(BenshiRadio.readSettingsRequest())
    }

    func radioControl(_ message: BenshiMessage) {
        if let status = BenshiRadio.status(from: message) {
            radioPanel.channel = "Channel \(status.channelID)\(status.transmitting ? " TX" : "")\(status.receiving ? " RX" : "")"
        }
        if let battery = BenshiRadio.batteryPercent(from: message) {
            radioPanel.battery = "Battery \(battery)%"
        }
        if let volume = BenshiRadio.volume(from: message) {
            radioPanel.volume = volume
        }
        if message.isReply, message.command == BenshiCommand.readSettings, message.body.count > 1 {
            settingsBody = message.body.dropFirst()
        }
        if let channel = BenshiRadio.channel(from: message), message.body.count > 1 {
            channelBodies[channel.id] = message.body.dropFirst()
            if let index = radioPanel.channels.firstIndex(where: { $0.id == channel.id }) {
                radioPanel.channels[index] = channel
            } else {
                radioPanel.channels.append(channel)
                radioPanel.channels.sort { $0.id < $1.id }
            }
            radioPanel.callingWarning = radioPanel.callingWarning || TeamPolicy.isNationalAPRSCallingFrequency(megahertz: channel.receiveMHz)
        }
    }

    func selectRadioChannel(_ id: Int) {
        guard let settingsBody, let patched = BenshiRadio.settingSelectedChannel(id, in: settingsBody) else { return }
        self.settingsBody = patched
        radio.send(BenshiRadio.writeSettingsRequest(patched))
        radioPanel.channel = "Channel \(id)"
    }

    func stepRadioChannel(_ delta: Int) {
        let ids = radioPanel.channels.map(\.id).sorted()
        guard !ids.isEmpty else { return }
        let current = settingsBody.flatMap(BenshiRadio.selectedChannel(in:)) ?? ids[0]
        let index = ids.firstIndex(of: current) ?? 0
        selectRadioChannel(ids[(index + delta + ids.count) % ids.count])
    }

    func setRadioPower(_ power: TXPower) {
        guard let id = settingsBody.flatMap(BenshiRadio.selectedChannel(in:)) ?? radioPanel.channels.first?.id,
              let raw = channelBodies[id],
              let patched = BenshiRadio.setPower(power, inChannelBody: raw)
        else { return }
        channelBodies[id] = patched
        radioPanel.power = power
        radio.send(BenshiRadio.writeChannelRequest(patched))
    }

    func setRadioVolume(_ level: Int) {
        radioPanel.volume = level
        radio.send(BenshiRadio.setVolumeRequest(level))
    }

    func addRosterCallsign() {
        guard let base = TeamPolicy.baseCallsign(rosterEntry) else { return }
        var config = engine.config
        if !config.rosterCallsigns.contains(base) {
            config.rosterCallsigns.append(base)
        }
        engine.config = config
        rosterEntry = ""
        saveSettings()
    }

    func setEmergencyEncryption(_ enabled: Bool) {
        guard operatingMode == .team else {
            emergencyEncryption = false
            return
        }
        if enabled && engine.emergencyKeys.isEmpty {
            engine.emergencyKeys = [TeamKey.generate()]
            saveTeamKeys()
        }
        emergencyEncryption = enabled
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(enabled ? "enabled" : "disabled")\n"
        encryptionLog += line
        if let data = encryptionLog.data(using: .utf8) {
            try? data.write(to: auditURL, options: .atomic)
        }
        saveSettings()
    }

    func teamKeyShareText() -> String? {
        engine.emergencyKeys.first?.shareText
    }

    func importTeamKey(_ text: String) {
        guard let key = TeamKey.parseShareText(text) else { return }
        var keys = engine.emergencyKeys.filter { $0.id != key.id }
        keys.insert(key, at: 0)
        engine.emergencyKeys = Array(keys.prefix(4))
        saveTeamKeys()
    }

    func rotateTeamKey() {
        var keys = engine.emergencyKeys
        keys.insert(TeamKey.generate(), at: 0)
        engine.emergencyKeys = Array(keys.prefix(4))
        saveTeamKeys()
    }

    private func loadTeamKeys() {
        guard let data = TAKCredentialStore.load(account: "team-keys"),
              let texts = try? JSONDecoder().decode([String].self, from: data)
        else { return }
        engine.emergencyKeys = texts.compactMap(TeamKey.parseShareText)
        if let log = try? String(contentsOf: auditURL, encoding: .utf8) {
            encryptionLog = log
        }
    }

    private func saveTeamKeys() {
        let texts = engine.emergencyKeys.map(\.shareText)
        if let data = try? JSONEncoder().encode(texts) {
            _ = TAKCredentialStore.save(account: "team-keys", data: data)
        }
    }

    private func forgetCertificateFiles() {
        let directory = configURL.deletingLastPathComponent()
        for name in ["upstream-trust.p12", "upstream-client.p12"] {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    private func persistSnapshot() {
        if let data = try? JSONEncoder().encode(engine.snapshot()) {
            try? data.write(to: snapshotURL, options: .atomic)
        }
    }
}

extension AppModel: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let next = response.actionIdentifier == "channel.next"
        MainActor.assumeIsolated {
            self.stepRadioChannel(next ? 1 : -1)
        }
        completionHandler()
    }
}

struct RadioPanel {
    var battery = "Battery unknown"
    var channel = "Channel unknown"
    var volume = 0
    var power = TXPower.low
    var channels: [RadioChannel] = []
    var callingWarning = false
    var control = false
}

struct RadioAdvertisement: Identifiable, Equatable {
    var id: UUID
    var name: String
    var rssi: Int
}
