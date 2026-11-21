// Copyright 2026 Josh Howard
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import UniformTypeIdentifiers
import UVBridgeCore

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            FieldBanner(text: model.modeSummary)
                .accessibilityLabel("Link mode. \(model.modeSummary)")
            TabView {
                RadioView()
                    .tabItem { Label("Radio", systemImage: "antenna.radiowaves.left.and.right") }
                StationsView()
                    .tabItem { Label("Stations", systemImage: "mappin.and.ellipse") }
                LogView()
                    .tabItem { Label("Log", systemImage: "list.bullet.rectangle") }
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
            .tint(FieldTheme.amber)
        }
        .background(FieldTheme.background)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
    }
}

struct RadioView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(model.modeName.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FieldTheme.amber)
                Text(model.radioStatus)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(FieldTheme.text)
                Text("iTAK stays on \(model.localConnect). You import that once and leave it there, on the trail and on the network.")
                    .font(.subheadline)
                    .foregroundStyle(FieldTheme.dim)
                if let hint = model.radioHint {
                    Text(hint)
                        .font(.subheadline)
                        .foregroundStyle(FieldTheme.warn)
                        .padding(12)
                        .background(FieldTheme.panel)
                }
                if model.discovered.isEmpty {
                    FieldEmpty(
                        title: "No KISS TNC advertising",
                        detail: "On a UV-PRO, VR-N76, or GA-5WB open Menu, General Settings, and turn KISS TNC on. Quit the radio's own app. The Bluetooth link is exclusive."
                    )
                } else {
                    ForEach(model.discovered) { radio in
                        Button {
                            model.connectRadio(radio.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(radio.name).foregroundStyle(FieldTheme.text)
                                    Text(radio.id.uuidString.prefix(8) + "…").font(.caption.monospaced()).foregroundStyle(FieldTheme.dim)
                                }
                                Spacer()
                                Text("\(radio.rssi) dBm").font(.caption.monospaced()).foregroundStyle(FieldTheme.amber)
                            }
                            .padding(12)
                            .background(FieldTheme.panel)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !model.refusals.isEmpty {
                    Text(model.refusals.joined(separator: "\n"))
                        .font(.caption.monospaced())
                        .foregroundStyle(FieldTheme.warn)
                }
            }
            .padding(16)
        }
        .background(FieldTheme.background)
    }
}

struct StationsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if model.stations.isEmpty {
                    FieldEmpty(
                        title: "No stations yet",
                        detail: "Connect the radio to hear APRS. When your TAK server is reachable, stations you have already heard on RF update in place instead of appearing twice."
                    )
                }
                ForEach(model.stations) { station in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(station.callsign).font(.headline.monospaced()).foregroundStyle(FieldTheme.text)
                            Spacer()
                            Text(station.sources.map(\.rawValue).sorted().joined(separator: "+").uppercased())
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(FieldTheme.background)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(FieldTheme.amber)
                        }
                        if let lat = station.latitude, let lon = station.longitude {
                            Text(String(format: "%.5f, %.5f", lat, lon))
                                .font(.caption.monospaced())
                                .foregroundStyle(FieldTheme.dim)
                        }
                        if !station.comment.isEmpty {
                            Text(station.comment).font(.subheadline).foregroundStyle(FieldTheme.text)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(FieldTheme.panel)
                }
            }
            .padding(16)
        }
        .background(FieldTheme.background)
    }
}

struct LogView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showTX = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("Log", selection: $showTX) {
                Text("Heard").tag(false)
                Text("Transmitted").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(12)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if showTX {
                        if model.txLog.isEmpty {
                            FieldEmpty(title: "Nothing transmitted", detail: "Every frame that goes to the radio is listed here. A blank callsign cannot key the transmitter.")
                        }
                        ForEach(model.txLog) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.summary).foregroundStyle(FieldTheme.text)
                                Text(entry.monitor).font(.caption.monospaced()).foregroundStyle(FieldTheme.dim)
                                Text(entry.hex).font(.caption2.monospaced()).foregroundStyle(FieldTheme.amber).lineLimit(3)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(FieldTheme.panel)
                        }
                    } else {
                        if model.packetLog.isEmpty {
                            FieldEmpty(title: "The log is empty", detail: "Heard packets, queued server traffic, and refusals show up here.")
                        }
                        ForEach(model.packetLog) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.direction.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(FieldTheme.amber)
                                Text(entry.summary).font(.caption.monospaced()).foregroundStyle(FieldTheme.text)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(FieldTheme.panel)
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .background(FieldTheme.background)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var importing = false

    var body: some View {
        Form {
            Section("Operator") {
                TextField("Callsign", text: $model.callsign)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Stepper("SSID \(model.ssid == 0 ? "none" : String(model.ssid))", value: $model.ssid, in: 0...15)
                Text("Leave this blank until it is your own callsign. Josh Howard uses WA7BRM-7. The app will not transmit until a callsign is set.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Beacon") {
                Toggle("Beacon my position", isOn: $model.beaconEnabled)
                TextField("Comment", text: $model.comment)
                TextField("Path", text: $model.path)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Picker("Symbol", selection: $model.symbol) {
                    Text("Person").tag("[")
                    Text("Car").tag(">")
                    Text("Truck").tag("k")
                    Text("House").tag("-")
                }
            }
            Section("iTAK") {
                Text(model.localConnect).font(.body.monospaced())
                Text(OperatorHint.addToITAKOnce).font(.footnote)
                ShareLink(item: model.packageFile()) {
                    Label("Add to iTAK", systemImage: "square.and.arrow.up")
                }
            }
            Section("Your TAK server") {
                TextField("Host", text: $model.upstreamHost)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Port", text: $model.upstreamPort)
                    .keyboardType(.numberPad)
                Toggle("TLS", isOn: $model.upstreamTLS)
                Toggle("Show the whole server map", isOn: $model.mirrorServer)
                Text("iTAK does not get this address. The bridge uses it when the phone can reach it, and queues when it cannot.")
                    .font(.footnote)
                Button("Import enrollment package") { importing = true }
                if !model.importNote.isEmpty {
                    Text(model.importNote).font(.footnote)
                }
            }
            Section("Part 97") {
                Toggle("Allow other people's chat onto RF", isOn: $model.allowThirdParty)
                Text("Off by default. Amateur radio is not encrypted here. TLS to your TAK server is on the internet, not on the air.")
                    .font(.footnote)
            }
            Section("About") {
                Text("\(UVBridgeCore.name) \(UVBridgeCore.version)")
                Text("\(UVBridgeCore.maintainer), \(UVBridgeCore.maintainerCallsign) (\(UVBridgeCore.maintainerLicenseClass)), \(UVBridgeCore.maintainerQTH).")
                Text("Apache-2.0. An open bridge for iTAK and a BLE KISS radio. Not affiliated with TAK, iTAK, or BTECH.")
                    .font(.footnote)
            }
        }
        .scrollContentBackground(.hidden)
        .background(FieldTheme.background)
        .onChange(of: model.callsign) { _, _ in model.saveSettings() }
        .onChange(of: model.ssid) { _, _ in model.saveSettings() }
        .onChange(of: model.path) { _, _ in model.saveSettings() }
        .onChange(of: model.comment) { _, _ in model.saveSettings() }
        .onChange(of: model.symbol) { _, _ in model.saveSettings() }
        .onChange(of: model.beaconEnabled) { _, _ in model.saveSettings() }
        .onChange(of: model.upstreamHost) { _, _ in model.saveSettings() }
        .onChange(of: model.upstreamPort) { _, _ in model.saveSettings() }
        .onChange(of: model.upstreamTLS) { _, _ in model.saveSettings() }
        .onChange(of: model.mirrorServer) { _, _ in model.saveSettings() }
        .onChange(of: model.allowThirdParty) { _, _ in model.saveSettings() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.zip]) { result in
            if case .success(let url) = result, let data = try? Data(contentsOf: url) {
                model.importServerPackage(data)
            }
        }
    }
}
