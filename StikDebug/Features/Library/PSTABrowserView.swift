import SwiftUI

struct PSTABrowserView: View {
    @StateObject private var gtfs = GTFSService.shared
    @StateObject private var store = RouteStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedRoute: GTFSRoute?
    @State private var selectedTrip: GTFSTrip?
    @State private var savedMessage: String?
    @State private var showSavedAlert = false

    var filteredRoutes: [GTFSRoute] {
        if searchText.isEmpty { return gtfs.routes }
        return gtfs.routes.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.shortName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if gtfs.isLoading {
                    ProgressView("Loading PSTA routes…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if gtfs.routes.isEmpty {
                    emptyState
                } else {
                    routeList
                }
            }
            .navigationTitle("PSTA Routes")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search routes")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await gtfs.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(gtfs.isLoading)
                }
            }
            .alert("Saved", isPresented: $showSavedAlert) {
                Button("OK") {}
            } message: {
                Text(savedMessage ?? "")
            }
        }
        .task {
            if gtfs.routes.isEmpty { await gtfs.refresh() }
        }
    }

    private var routeList: some View {
        List(filteredRoutes) { route in
            NavigationLink {
                TripPickerView(route: route) { trip in
                    saveRoute(route: route, trip: trip)
                }
            } label: {
                HStack(spacing: 12) {
                    if let color = route.color, !color.isEmpty {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: color) ?? .accentColor)
                            .frame(width: 32, height: 32)
                            .overlay(Text(route.shortName).font(.caption2.bold()).foregroundStyle(.white))
                    } else {
                        Image(systemName: "bus.fill")
                            .foregroundStyle(.accentColor)
                            .frame(width: 32)
                    }
                    VStack(alignment: .leading) {
                        Text(route.displayName).font(.headline)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bus.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No PSTA Routes Loaded")
                .font(.title3.bold())
            if let error = gtfs.loadError {
                Text(error).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Button("Download PSTA Feed") {
                Task { await gtfs.refresh() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func saveRoute(route: GTFSRoute, trip: GTFSTrip) {
        let name = "\(route.displayName) – \(trip.headsign)"
        if let saved = gtfs.buildRoute(routeID: route.id, tripID: trip.id, name: name) {
            store.save(saved)
            savedMessage = "\"\(name)\" saved to Library."
            showSavedAlert = true
        }
    }
}

// MARK: - Trip picker

private struct TripPickerView: View {
    let route: GTFSRoute
    let onSelect: (GTFSTrip) -> Void
    @Environment(\.dismiss) private var dismiss

    var trips: [GTFSTrip] { GTFSService.shared.trips(forRouteID: route.id) }

    var body: some View {
        List(trips) { trip in
            Button {
                onSelect(trip)
                dismiss()
            } label: {
                VStack(alignment: .leading) {
                    Text(trip.headsign.isEmpty ? "Trip \(trip.id)" : trip.headsign)
                        .font(.headline)
                    Text("ID: \(trip.id)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Select Trip")
    }
}

// MARK: - Color hex helper

private extension Color {
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h = String(h.dropFirst()) }
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
        self.init(
            red:   Double((val >> 16) & 0xFF) / 255,
            green: Double((val >> 8)  & 0xFF) / 255,
            blue:  Double( val        & 0xFF) / 255
        )
    }
}
