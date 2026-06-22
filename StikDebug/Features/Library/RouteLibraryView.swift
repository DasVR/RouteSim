import SwiftUI

struct RouteLibraryView: View {
    @StateObject private var store = RouteStore.shared
    @State private var showingPSTABrowser = false
    @State private var selectedRoute: SavedRoute?
    @State private var showDeleteConfirm = false
    @State private var routeToDelete: SavedRoute?

    var body: some View {
        Group {
            if store.routes.isEmpty {
                emptyState
            } else {
                routeList
            }
        }
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingPSTABrowser = true
                } label: {
                    Label("PSTA Routes", systemImage: "bus")
                }
            }
        }
        .sheet(isPresented: $showingPSTABrowser) {
            PSTABrowserView()
        }
        .confirmationDialog("Delete Route", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let r = routeToDelete { store.delete(r) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private var routeList: some View {
        List {
            ForEach(store.routes) { route in
                RouteRowView(route: route)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            routeToDelete = route
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Button {
                            shareGPX(route)
                        } label: {
                            Label("Export GPX", systemImage: "square.and.arrow.up")
                        }
                        .tint(.blue)
                    }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "map.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("No Saved Routes")
                .font(.title3.bold())
            Text("Save a route from the Simulate tab, or load a PSTA bus route.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Browse PSTA Routes") {
                showingPSTABrowser = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func shareGPX(_ route: SavedRoute) {
        let data = RouteStore.shared.exportGPX(route)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(route.name).gpx")
        try? data.write(to: url)
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .windows.first?
            .rootViewController?
            .present(av, animated: true)
    }
}

private struct RouteRowView: View {
    let route: SavedRoute

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: route.mode.systemImage)
                .font(.title2)
                .foregroundStyle(.accentColor)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(route.name).font(.headline)
                HStack(spacing: 8) {
                    Text(route.mode.displayName)
                    Text("·")
                    Text(formatDistance(route.totalDistanceMeters))
                    Text("·")
                    Text("\(route.waypoints.count) pts")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDistance(_ m: Double) -> String {
        m >= 1000 ? String(format: "%.1f km", m / 1000) : String(format: "%.0f m", m)
    }
}

// MARK: - LibraryView entry (referenced by RootView)

struct LibraryView: View {
    var body: some View {
        RouteLibraryView()
    }
}
