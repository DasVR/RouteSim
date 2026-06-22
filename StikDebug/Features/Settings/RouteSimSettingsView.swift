import SwiftUI

struct RouteSimSettingsView: View {
    @AppStorage(UserDefaults.Keys.targetDeviceIP)  private var deviceIP = DeviceConnectionContext.defaultTargetIPAddress
    @AppStorage(UserDefaults.Keys.pstaGTFSFeedURL) private var gtfsFeedURL = GTFSService.defaultFeedURL
    @AppStorage("keepAliveAudio")    private var keepAliveAudio = true
    @AppStorage("keepAliveLocation") private var keepAliveLocation = true
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true

    @StateObject private var tunnelManager = TunnelManager.shared
    @State private var showClearRoutesConfirm = false

    var body: some View {
        Form {
            // Tunnel / Connection
            Section("Connection") {
                HStack {
                    Label("Tunnel", systemImage: "network")
                    Spacer()
                    if tunnelManager.isConnected {
                        Label("Connected", systemImage: "circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    } else {
                        Button("Reconnect") { startTunnelInBackground() }
                            .font(.caption)
                    }
                }

                LabeledContent("Device IP") {
                    TextField("10.7.0.1", text: $deviceIP)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                        .frame(maxWidth: 140)
                }
            }

            // Pairing
            Section("Pairing File") {
                PairingFileSectionView()
            }

            // Keep-alive background
            Section("Background Keep-Alive") {
                Toggle("Silent Audio", isOn: $keepAliveAudio)
                Toggle("Location Update", isOn: $keepAliveLocation)
                Text("Both are recommended to prevent iOS from stopping the simulation when the screen locks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // GTFS
            Section("PSTA GTFS Feed") {
                LabeledContent("Feed URL") {
                    TextField("https://…", text: $gtfsFeedURL)
                        .textFieldStyle(.roundedBorder)
                }
                Button("Refresh Feed Now") {
                    Task { await GTFSService.shared.refresh() }
                }
                if let updated = GTFSService.shared.lastUpdated {
                    Text("Last updated: \(updated.formatted())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Reset to Default URL") {
                    gtfsFeedURL = GTFSService.defaultFeedURL
                }
                .foregroundStyle(.orange)
            }

            // Data management
            Section("Data") {
                Button("Clear All Saved Routes", role: .destructive) {
                    showClearRoutesConfirm = true
                }
            }

            // Re-run onboarding
            Section("Setup") {
                Button("Show Onboarding Again") {
                    hasCompletedOnboarding = false
                }
            }

            // About
            Section("About") {
                LabeledContent("App", value: "RouteSim")
                LabeledContent("Version", value: appVersion)
                LabeledContent("Based on", value: "StikDebug (StephenDev0)")
                LabeledContent("Life360 Note", value: "GPS spoofing only — Core Motion not affected")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Clear All Routes?", isPresented: $showClearRoutesConfirm) {
            Button("Clear All", role: .destructive) {
                RouteStore.shared.routes.forEach { RouteStore.shared.delete($0) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

// MARK: - Pairing file section

private struct PairingFileSectionView: View {
    @State private var showPicker = false
    @State private var hasPairing = FileManager.default.fileExists(
        atPath: PairingFileStore.prepareURL().path)

    var body: some View {
        if hasPairing {
            HStack {
                Label("Pairing file imported", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                Button("Replace") { showPicker = true }
                    .font(.caption)
            }
        } else {
            Button("Import Pairing File") { showPicker = true }
        }
    }
}
