import SwiftUI
import MapKit

struct RouteEditorView: View {
    @StateObject private var vm = SimulateViewModel()
    @StateObject private var tunnelManager = TunnelManager.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            mapLayer

            VStack(spacing: 0) {
                if let prompt = vm.placementPrompt {
                    Text(prompt)
                        .font(.subheadline.bold())
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial)
                        .clipShape(Capsule())
                        .padding(.top, 8)
                        .padding(.horizontal)
                }

                Spacer()

                controlsOverlay
            }
        }
        .navigationTitle("RouteSim")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
        .onAppear {
            vm.startUserLocationUpdates()
            if vm.placementPhase == .idle {
                vm.beginNewRoute(for: vm.selectedMode)
            }
        }
        .onDisappear {
            vm.stopUserLocationUpdates()
        }
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
        MapReader { proxy in
            Map(position: $vm.mapPosition) {
                UserAnnotation()

                if let start = vm.startPinCoordinate {
                    let label = vm.selectedMode == .standstill ? "Hold" : "Start"
                    Annotation(label, coordinate: start) {
                        if vm.selectedMode == .standstill {
                            HoldPin()
                        } else {
                            StartPin()
                        }
                    }
                }

                if let end = vm.endPinCoordinate {
                    Annotation("End", coordinate: end) {
                        EndPin()
                    }
                }

                if let coord = vm.currentCoordinate {
                    Annotation("", coordinate: coord) {
                        Circle()
                            .fill(.blue)
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }

                if let poly = vm.routePolyline {
                    MapPolyline(poly)
                        .stroke(.blue, lineWidth: 6)
                }
            }
            .mapStyle(.standard)
            .onTapGesture { screenPoint in
                if let coordinate = proxy.convert(screenPoint, from: .local) {
                    vm.handleMapTap(at: coordinate)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Controls overlay

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            modeBar
                .background(.regularMaterial)

            if vm.isPlaying || vm.stats.odometer > 0 {
                LiveStatsView(stats: vm.stats)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

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
                        vm.selectMode(mode)
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
            Button {
                vm.requestUserLocationAccess()
                vm.useCurrentLocationAsStart()
            } label: {
                Image(systemName: "location.fill")
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button("Save Route") { vm.showSaveSheet = true }
                Button("Clear Route", role: .destructive) {
                    vm.beginNewRoute(for: vm.selectedMode)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
}

// MARK: - Map pins

private struct StartPin: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.green)
                .frame(width: 28, height: 28)
            Image(systemName: "flag.fill")
                .foregroundStyle(.white)
                .font(.caption)
        }
        .shadow(radius: 3)
    }
}

private struct EndPin: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.red)
                .frame(width: 28, height: 28)
            Image(systemName: "mappin")
                .foregroundStyle(.white)
                .font(.caption)
        }
        .shadow(radius: 3)
    }
}

private struct HoldPin: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.orange)
                .frame(width: 28, height: 28)
            Image(systemName: "pause.fill")
                .foregroundStyle(.white)
                .font(.caption)
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
