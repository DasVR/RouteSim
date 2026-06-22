import Foundation
import CoreLocation

// MARK: - GTFSService
//
// Downloads, caches, and parses the PSTA (Pinellas Suncoast Transit Authority) GTFS feed.
// The feed is a ZIP file containing CSV text files.
// Feed URL is user-configurable in Settings (defaults to the PSTA public URL).
//
// Cache location: Caches/GTFS/<feedHash>/
// Once cached the feed is not re-downloaded unless the user taps "Refresh".

final class GTFSService: ObservableObject {
    static let shared = GTFSService()

    @Published private(set) var routes: [GTFSRoute] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?
    @Published private(set) var lastUpdated: Date?

    // Default PSTA GTFS static feed URL (configurable in Settings)
    static let defaultFeedURL = "https://www.psta.net/media/gtfs/GTFS.zip"

    private var currentFeedURL: URL {
        let stored = UserDefaults.standard.string(forKey: UserDefaults.Keys.pstaGTFSFeedURL) ?? ""
        return URL(string: stored) ?? URL(string: GTFSService.defaultFeedURL)!
    }

    private let cacheRoot: URL = {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GTFS", isDirectory: true)
    }()

    private var cacheDir: URL { cacheRoot.appendingPathComponent("psta", isDirectory: true) }

    // MARK: - Parsed data (in-memory after load)
    private var stops: [String: GTFSStop] = [:]       // stop_id → GTFSStop
    private var trips: [String: GTFSTrip] = [:]       // trip_id → GTFSTrip
    private var stopTimes: [String: [GTFSStopTime]] = [:]  // trip_id → sorted stop times
    private var shapes: [String: [CLLocationCoordinate2D]] = [:] // shape_id → coords

    private init() {
        Task { await loadCachedIfAvailable() }
    }

    // MARK: - Public API

    /// Fetch the feed (download if not cached), parse, and populate `routes`.
    func refresh() async {
        await MainActor.run { isLoading = true; loadError = nil }
        do {
            let zipURL = try await downloadFeed()
            let extracted = try extractZIP(at: zipURL)
            try await parse(from: extracted)
            await MainActor.run {
                self.isLoading = false
                self.lastUpdated = Date()
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.loadError = error.localizedDescription
            }
        }
    }

    /// Build a SavedRoute from a GTFS route + trip selection.
    func buildRoute(routeID: String, tripID: String, name: String) -> SavedRoute? {
        guard let trip = trips[tripID] else { return nil }
        let times = stopTimes[tripID] ?? []

        let waypoints: [Waypoint]
        if let shapeID = trip.shapeID, let shapePts = shapes[shapeID] {
            waypoints = shapePts.map { Waypoint(coordinate: $0) }
        } else {
            waypoints = times.compactMap { st -> Waypoint? in
                guard let stop = stops[st.stopID] else { return nil }
                return Waypoint(coordinate: stop.coordinate, name: stop.name)
            }
        }
        guard !waypoints.isEmpty else { return nil }

        let routeStops: [RouteStop] = times.compactMap { st in
            guard let stop = stops[st.stopID] else { return nil }
            return RouteStop(
                coordinate: stop.coordinate,
                name: stop.name,
                dwell: st.dwellSeconds,
                gtfsID: st.stopID
            )
        }

        return SavedRoute(
            name: name,
            mode: .bus,
            waypoints: waypoints,
            stops: routeStops
        )
    }

    /// Trips available for a given route_id (for the trip picker).
    func trips(forRouteID id: String) -> [GTFSTrip] {
        trips.values.filter { $0.routeID == id }
    }

    // MARK: - Download

    private func downloadFeed() async throws -> URL {
        let dest = cacheRoot.appendingPathComponent("feed.zip")
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        let (tmp, response) = try await URLSession.shared.download(from: currentFeedURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        if FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }

    // MARK: - ZIP extraction (manual — no ZIPFoundation dependency needed for GTFS CSVs)
    //
    // GTFS ZIP files are ZIP32 format. We use a simple local-file-header scan to extract
    // the CSV text files we need (routes.txt, trips.txt, stops.txt, stop_times.txt, shapes.txt).

    private func extractZIP(at zipURL: URL) throws -> URL {
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let data = try Data(contentsOf: zipURL, options: .mappedIfSafe)
        var offset = 0
        let needed: Set<String> = ["routes.txt","trips.txt","stops.txt","stop_times.txt","shapes.txt"]

        while offset + 30 <= data.count {
            let sig = data.loadUInt32LE(at: offset)
            guard sig == 0x04034b50 else { break }   // local file header signature

            let nameLen  = Int(data.loadUInt16LE(at: offset + 26))
            let extraLen = Int(data.loadUInt16LE(at: offset + 28))
            let compSize = Int(data.loadUInt32LE(at: offset + 18))
            let method   = data.loadUInt16LE(at: offset + 8)

            let nameStart  = offset + 30
            let nameEnd    = nameStart + nameLen
            let dataStart  = nameEnd + extraLen
            let dataEnd    = dataStart + compSize

            guard dataEnd <= data.count else { break }

            if let name = String(data: data[nameStart..<nameEnd], encoding: .utf8),
               needed.contains(name.components(separatedBy: "/").last ?? "") {
                let fileData: Data
                if method == 0 {                        // stored (no compression)
                    fileData = data[dataStart..<dataEnd]
                } else {
                    // Deflate — fall back to system unzip for compressed entries
                    fileData = try decompressDeflate(data[dataStart..<dataEnd])
                }
                let dest = cacheDir.appendingPathComponent(
                    (name.components(separatedBy: "/").last)!)
                try fileData.write(to: dest, options: .atomic)
            }

            offset = dataEnd
        }
        return cacheDir
    }

    private func decompressDeflate(_ compressed: Data) throws -> Data {
        // Use zlib inflate (add zlib header bytes for CFData compatibility)
        var header = Data([0x78, 0x9C])
        header.append(compressed)
        return try (header as NSData).decompressed(using: .zlib) as Data
    }

    // MARK: - CSV parsing

    private func parse(from dir: URL) async throws {
        stops      = try parseStops(dir.appendingPathComponent("stops.txt"))
        trips      = try parseTrips(dir.appendingPathComponent("trips.txt"))
        stopTimes  = try parseStopTimes(dir.appendingPathComponent("stop_times.txt"))
        shapes     = parseShapes(dir.appendingPathComponent("shapes.txt"))
        let parsed = try parseRoutes(dir.appendingPathComponent("routes.txt"))

        await MainActor.run { self.routes = parsed.sorted { $0.shortName < $1.shortName } }
    }

    private func parseRoutes(_ url: URL) throws -> [GTFSRoute] {
        let rows = try CSVParser.parse(url: url)
        return rows.compactMap { row -> GTFSRoute? in
            guard let id = row["route_id"] else { return nil }
            return GTFSRoute(
                id: id,
                shortName: row["route_short_name"] ?? "",
                longName:  row["route_long_name"] ?? "",
                color:     row["route_color"]
            )
        }
    }

    private func parseTrips(_ url: URL) throws -> [String: GTFSTrip] {
        let rows = try CSVParser.parse(url: url)
        var result: [String: GTFSTrip] = [:]
        for row in rows {
            guard let tid = row["trip_id"], let rid = row["route_id"] else { continue }
            result[tid] = GTFSTrip(
                id: tid,
                routeID: rid,
                headsign: row["trip_headsign"] ?? "",
                shapeID: row["shape_id"]
            )
        }
        return result
    }

    private func parseStops(_ url: URL) throws -> [String: GTFSStop] {
        let rows = try CSVParser.parse(url: url)
        var result: [String: GTFSStop] = [:]
        for row in rows {
            guard let sid = row["stop_id"],
                  let latStr = row["stop_lat"], let lonStr = row["stop_lon"],
                  let lat = Double(latStr), let lon = Double(lonStr) else { continue }
            result[sid] = GTFSStop(
                id: sid, name: row["stop_name"] ?? sid,
                latitude: lat, longitude: lon
            )
        }
        return result
    }

    private func parseStopTimes(_ url: URL) throws -> [String: [GTFSStopTime]] {
        let rows = try CSVParser.parse(url: url)
        var result: [String: [GTFSStopTime]] = [:]
        for row in rows {
            guard let tid  = row["trip_id"],
                  let arr  = row["arrival_time"],
                  let dep  = row["departure_time"],
                  let sid  = row["stop_id"],
                  let seqS = row["stop_sequence"], let seq = Int(seqS) else { continue }
            let st = GTFSStopTime(tripID: tid, arrivalTime: arr, departureTime: dep,
                                  stopID: sid, stopSequence: seq)
            result[tid, default: []].append(st)
        }
        result.keys.forEach { result[$0]?.sort { $0.stopSequence < $1.stopSequence } }
        return result
    }

    private func parseShapes(_ url: URL) -> [String: [CLLocationCoordinate2D]] {
        guard let rows = try? CSVParser.parse(url: url) else { return [:] }
        var raw: [String: [(seq: Int, coord: CLLocationCoordinate2D)]] = [:]
        for row in rows {
            guard let sid = row["shape_id"],
                  let latStr = row["shape_pt_lat"], let lonStr = row["shape_pt_lon"],
                  let lat = Double(latStr), let lon = Double(lonStr),
                  let seqStr = row["shape_pt_sequence"], let seq = Int(seqStr) else { continue }
            raw[sid, default: []].append((seq, CLLocationCoordinate2D(latitude: lat, longitude: lon)))
        }
        return raw.mapValues { $0.sorted { $0.seq < $1.seq }.map(\.coord) }
    }

    // MARK: - Cache load

    private func loadCachedIfAvailable() async {
        guard FileManager.default.fileExists(atPath: cacheDir.path) else { return }
        guard let rows = try? CSVParser.parse(url: cacheDir.appendingPathComponent("routes.txt")) else { return }
        let parsed = rows.compactMap { row -> GTFSRoute? in
            guard let id = row["route_id"] else { return nil }
            return GTFSRoute(id: id, shortName: row["route_short_name"] ?? "",
                             longName: row["route_long_name"] ?? "", color: row["route_color"])
        }
        await MainActor.run { self.routes = parsed.sorted { $0.shortName < $1.shortName } }
    }
}

// MARK: - Minimal CSV parser

private enum CSVParser {
    static func parse(url: URL) throws -> [[String: String]] {
        let text = try String(contentsOf: url, encoding: .utf8)
        var lines = text.components(separatedBy: "\n")
        guard let header = lines.first else { return [] }
        let keys = header.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
        lines.removeFirst()
        return lines.compactMap { line -> [String: String]? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let values = split(csv: trimmed)
            guard values.count == keys.count else { return nil }
            return Dictionary(uniqueKeysWithValues: zip(keys, values))
        }
    }

    // Handles quoted fields with commas inside
    private static func split(csv line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for char in line {
            if char == "\"" { inQuotes.toggle() }
            else if char == "," && !inQuotes { fields.append(current); current = "" }
            else { current.append(char) }
        }
        fields.append(current)
        return fields
    }
}

// MARK: - Data helpers for ZIP parsing

private extension Data {
    func loadUInt16LE(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }
    func loadUInt32LE(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return UInt32(self[offset])       | (UInt32(self[offset+1]) << 8)
             | (UInt32(self[offset+2]) << 16) | (UInt32(self[offset+3]) << 24)
    }
}
