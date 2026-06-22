import Foundation

// MARK: - RouteStore
//
// Persists SavedRoutes as individual JSON files in
// Application Support / Routes / <uuid>.json
// Each file is human-readable, diff-able, and can be
// shared as a plain JSON attachment.

final class RouteStore: ObservableObject {
    static let shared = RouteStore()

    @Published private(set) var routes: [SavedRoute] = []

    private let directory: URL = {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("Routes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {
        load()
    }

    // MARK: - CRUD

    func save(_ route: SavedRoute) {
        var r = route
        r.updatedAt = Date()
        let url = fileURL(for: r.id)
        guard let data = try? encoder.encode(r) else { return }
        try? data.write(to: url, options: .atomic)
        if let idx = routes.firstIndex(where: { $0.id == r.id }) {
            routes[idx] = r
        } else {
            routes.insert(r, at: 0)
        }
    }

    func delete(_ route: SavedRoute) {
        try? FileManager.default.removeItem(at: fileURL(for: route.id))
        routes.removeAll { $0.id == route.id }
    }

    func delete(at offsets: IndexSet) {
        offsets.map { routes[$0] }.forEach(delete)
    }

    // MARK: - GPX export

    func exportGPX(_ route: SavedRoute) -> Data {
        var gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="RouteSim">
          <trk>
            <name>\(route.name)</name>
            <trkseg>
        """
        for wp in route.waypoints {
            gpx += "\n      <trkpt lat=\"\(wp.latitude)\" lon=\"\(wp.longitude)\">"
            if let n = wp.name { gpx += "<name>\(n)</name>" }
            gpx += "</trkpt>"
        }
        gpx += "\n    </trkseg>\n  </trk>\n</gpx>"
        return Data(gpx.utf8)
    }

    // MARK: - Private

    private func load() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        )) ?? []
        routes = urls
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(SavedRoute.self, from: Data(contentsOf: $0)) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }
}
