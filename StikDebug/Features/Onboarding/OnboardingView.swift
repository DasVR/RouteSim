import SwiftUI

struct OnboardingView: View {
    var onComplete: () -> Void

    @State private var step: OnboardingStep = .welcome
    @State private var pairingImported = false
    @State private var showPairingPicker = false

    enum OnboardingStep: Int, CaseIterable {
        case welcome, pairing, vpn, developerMode, complete
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                stepContent
                Spacer()
                navigationButtons
            }
            .padding(24)
            .navigationTitle("Setup RouteSim")
            .navigationBarTitleDisplayMode(.inline)
        }
        .fileImporter(
            isPresented: $showPairingPicker,
            allowedContentTypes: PairingFileStore.supportedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                do {
                    try PairingFileStore.importFromPicker(url)
                    pairingImported = true
                } catch {
                    showAlert(title: "Import Failed", message: error.localizedDescription, showOk: true)
                }
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            OnboardingStepView(
                icon: "location.fill",
                title: "Welcome to RouteSim",
                message: "RouteSim spoofs your device's GPS location along a realistic route — Walk, Bike, Drive, or Bus — with proper speed and course so apps like Life360 accurately detect your movement.",
                tint: .accentColor
            )

        case .pairing:
            VStack(spacing: 16) {
                OnboardingStepView(
                    icon: "key.fill",
                    title: "Import Pairing File",
                    message: "RouteSim needs a pairing file to communicate with your device's debug services. Generate one with `pymobiledevice3` on a trusted computer and import it here.",
                    tint: .orange
                )
                if pairingImported || FileManager.default.fileExists(atPath: PairingFileStore.prepareURL().path) {
                    Label("Pairing file imported", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button("Import Pairing File (.plist)") {
                        showPairingPicker = true
                    }
                    .buttonStyle(.bordered)
                }
            }

        case .vpn:
            OnboardingStepView(
                icon: "network",
                title: "Connect LocalDevVPN",
                message: "Install the **LocalDevVPN** app from the App Store, then enable its VPN. This routes traffic to your device's debug services at 10.7.0.1.",
                tint: .purple
            )

        case .developerMode:
            OnboardingStepView(
                icon: "hammer.fill",
                title: "Enable Developer Mode",
                message: "On your iPhone: **Settings → Privacy & Security → Developer Mode** → turn On and reboot. Once enabled, RouteSim can inject simulated GPS.",
                tint: .blue
            )

        case .complete:
            OnboardingStepView(
                icon: "checkmark.circle.fill",
                title: "You're Ready!",
                message: "RouteSim is configured. Tap the map to add waypoints, choose a movement mode, and press Play.",
                tint: .green
            )
        }
    }

    @ViewBuilder
    private var navigationButtons: some View {
        HStack {
            if step != .welcome {
                Button("Back") {
                    withAnimation { step = OnboardingStep(rawValue: step.rawValue - 1) ?? .welcome }
                }
                .buttonStyle(.bordered)
            }
            Spacer()
            Button(step == .complete ? "Get Started" : "Next") {
                if step == .complete {
                    onComplete()
                } else {
                    withAnimation { step = OnboardingStep(rawValue: step.rawValue + 1) ?? .complete }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(step == .pairing && !pairingImported && !FileManager.default.fileExists(atPath: PairingFileStore.prepareURL().path))
        }

        // Step indicator
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { s in
                Circle()
                    .fill(s == step ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: s == step ? 10 : 6, height: s == step ? 10 : 6)
                    .animation(.spring, value: step)
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Reusable step card

struct OnboardingStepView: View {
    let icon: String
    let title: String
    let message: String
    let tint: Color

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundStyle(tint)
            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(try! AttributedString(
                markdown: message,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            ))
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }
}
