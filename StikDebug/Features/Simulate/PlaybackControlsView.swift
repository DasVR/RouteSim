import SwiftUI

struct PlaybackControlsView: View {
    @ObservedObject var vm: SimulateViewModel

    var body: some View {
        VStack(spacing: 12) {
            // Progress scrubber
            if vm.waypoints.count >= 2 {
                progressRow
            }

            // Transport controls
            transportRow

            // Speed + loop
            optionsRow
        }
        .padding(12)
    }

    // MARK: - Progress

    private var progressRow: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { vm.stats.progress },
                    set: { vm.scrub(to: $0) }
                ),
                in: 0...1
            )
            .tint(.accentColor)

            HStack {
                Text(formatTime(vm.stats.elapsed))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(etaLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Transport

    private var transportRow: some View {
        HStack(spacing: 24) {
            // Rewind to start
            Button {
                vm.stop()
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.title3)
            }
            .disabled(vm.stats.odometer == 0 && !vm.isPlaying)

            // Play / Pause
            Button {
                if vm.waypoints.count < 2 { return }
                if !vm.isPlaying && vm.stats.odometer == 0 {
                    Task { await vm.prepare(); vm.playPause() }
                } else {
                    vm.playPause()
                }
            } label: {
                ZStack {
                    if vm.isPreparing {
                        ProgressView()
                            .frame(width: 48, height: 48)
                    } else {
                        Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title)
                            .frame(width: 48, height: 48)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .clipShape(Circle())
            .disabled(vm.waypoints.count < 2 || vm.isPreparing)

            // Loop toggle
            Button {
                vm.loopEnabled.toggle()
            } label: {
                Image(systemName: vm.loopEnabled ? "repeat.1" : "repeat")
                    .font(.title3)
                    .foregroundStyle(vm.loopEnabled ? .accentColor : .secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Speed multiplier + loop

    private var optionsRow: some View {
        HStack {
            Text("Speed")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Speed", selection: $vm.speedMultiplier) {
                Text("0.5×").tag(0.5)
                Text("1×").tag(1.0)
                Text("2×").tag(2.0)
                Text("5×").tag(5.0)
                Text("10×").tag(10.0)
            }
            .pickerStyle(.segmented)
            .onChange(of: vm.speedMultiplier) { _, new in
                vm.player.speedMultiplier = new
            }

            if vm.speedMultiplier > 2 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .help("High multipliers inflate derived speed — use for preview only")
            }
        }
    }

    // MARK: - Helpers

    private var etaLabel: String {
        if vm.isPlaying, vm.stats.eta > 0 {
            return "ETA \(formatTime(vm.stats.eta))"
        }
        return formatDistance(vm.stats.totalDistance)
    }

    private func formatTime(_ s: TimeInterval) -> String {
        let t = Int(s)
        if t < 3600 { return String(format: "%d:%02d", t / 60, t % 60) }
        return String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
    }

    private func formatDistance(_ m: Double) -> String {
        if m >= 1000 { return String(format: "%.1f km", m / 1000) }
        return String(format: "%.0f m", m)
    }
}
