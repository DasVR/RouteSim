import SwiftUI
import MapKit

struct RouteEditorView: View {
    @StateObject private var vm = SimulateViewModel()
    @StateObject private var tunnelManager = TunnelManager.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            mapLayer
            controlsOverlay
        }
        .navigationTitle("RouteSim")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
        .fileImporter(
            isPresented: $vm.showFilePicker,
            allowedContentTypes: GPXImporter.supportedTypes,
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                vm.handleImport(url: url)
            }
        }
        .alert("Import Error", isPresented: .constant(vm.importError != nil)) {
            Button("OK") { vm.importError = nil }
        } message: {
            Text(vm.importError ?? "")
        }
        .sheet(isPresented: $vm.showSaveSheet) {
            SaveRouteSheet(name: $vm.routeName) {
                vm.saveToLibrary()
            }
        }
    }

    // MARK: - Map

    private var mapLayer: some View {
        Map(position: $vm.mapPosition) {
            // Waypoint markers
            ForEach(Array(vm.waypoints.enumerated()), id: \.element.id) { idx, wp in
                Annotation(wp.name ?? "WP \(idx + 1)", coordinate: wp.coordinate) {
                    WaypointPin(index: idx, isFirst: idx == 0, isLast: idx == vm.waypoints.count - 1)
                        .gesture(
                            DragGesture()
                                .onEnded { value in
                                    // MapKit coordinate conversion — approximation
                                }
                        )
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                vm.deleteWaypoint(wp)
                            }
                        }
                }
            }

            // Current simulated position
            if let coord = vm.currentCoordinate {
                Annotation("", coordinate: coord) {
                    Circle()
                        .fill(.blue)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }

            // Route overlay
            if let poly = vm.routePolyline {
                MapPolyline(poly)
                    .stroke(.blue.opacity(0.7), lineWidth: 4)
            }
        }
        .mapStyle(.standard)
        .onTapGesture { /* handled by map tap — MapKit TapGesture not directly supported */ }
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Controls overlay

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            // Mode + multiplier bar
            modeBar
                .background(.regularMaterial)

            // Live stats HUD (only while playing)
            if vm.isPlaying || vm.stats.odometer > 0 {
                LiveStatsView(stats: vm.stats)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Playback controls
            PlaybackControlsView(vm: vm)
                .background(.regularMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(radius: 8)
        .padding(.horizontal)
        .padding(.bottom, 8)
        .animation(.easeInOut, value: vm.isPlaying)
    }

    private var modeBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MovementMode.allCases) { mode in
                    ModeChip(mode: mode, isSelected: vm.selectedMode == mode) {
                        vm.selectedMode = mode
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                vm.showFilePicker = true
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button("Save Route") { vm.showSaveSheet = true }
                Button("Clear Waypoints", role: .destructive) {
                    vm.waypoints = []
                    vm.routePolyline = nil
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
}

// MARK: - Waypoint pin

private struct WaypointPin: View {
    let index: Int
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isFirst ? Color.green : (isLast ? Color.red : Color.blue))
                .frame(width: 28, height: 28)
            if isFirst {
                Image(systemName: "flag.fill").foregroundStyle(.white).font(.caption)
            } else if isLast {
                Image(systemName: "mappin").foregroundStyle(.white).font(.caption)
            } else {
                Text("\(index + 1)").foregroundStyle(.white).font(.caption2.bold())
            }
        }
        .shadow(radius: 3)
    }
}

// MARK: - Mode chip

private struct ModeChip: View {
    let mode: MovementMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(mode.displayName, systemImage: mode.systemImage)
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Save sheet

struct SaveRouteSheet: View {
    @Binding var name: String
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Route Name") {
                    TextField("Name", text: $name)
                }
            }
            .navigationTitle("Save Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(); dismiss() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - SimulateView entry point (referenced from RootView)

struct SimulateView: View {
    var body: some View {
        RouteEditorView()
    }
}
