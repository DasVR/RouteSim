import CoreLocation
import Foundation

// MARK: - Waypoint

struct Waypoint: Codable, Identifiable {
    var id: UUID = UUID()
    var latitude: Double
    var longitude: Double
    var name: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(coordinate: CLLocationCoordinate2D, name: String? = nil) {
        self.latitude  = coordinate.latitude
        self.longitude = coordinate.longitude
        self.name      = name
    }
}

// MARK: - RouteStop (for Bus mode)

struct RouteStop: Codable, Identifiable {
    var id: UUID = UUID()
    var latitude: Double
    var longitude: Double
    var name: String
    /// GTFS-derived dwell (departure - arrival in seconds).  Nil = randomised.
    var scheduledDwellSeconds: TimeInterval?
    /// GTFS stop_id, if loaded from a feed
    var gtfsStopID: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(coordinate: CLLocationCoordinate2D, name: String,
         dwell: TimeInterval? = nil, gtfsID: String? = nil) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.name = name
        self.scheduledDwellSeconds = dwell
        self.gtfsStopID = gtfsID
    }
}

// MARK: - ProfileOverride

struct ProfileOverride: Codable {
    var cruiseSpeedMps: Double?
    var speedMultiplier: Double?
    var loop: Bool?
}

// MARK: - SavedRoute

struct SavedRoute: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var mode: MovementMode
    var waypoints: [Waypoint]
    var stops: [RouteStop]
    var profileOverride: ProfileOverride?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var totalDistanceMeters: Double {
        let coords = waypoints.map(\.coordinate)
        return RouteGeometry.totalDistance(coords)
    }
}

// MARK: - GTFS route snapshot (used by GTFSService + PSTABrowserView)

struct GTFSRoute: Identifiable, Codable {
    var id: String          // route_id
    var shortName: String
    var longName: String
    var color: String?      // hex colour from GTFS

    var displayName: String {
        shortName.isEmpty ? longName : "\(shortName) – \(longName)"
    }
}

struct GTFSTrip: Identifiable, Codable {
    var id: String          // trip_id
    var routeID: String
    var headsign: String
    var shapeID: String?
}

struct GTFSStopTime: Codable {
    var tripID: String
    var arrivalTime: String    // "HH:MM:SS"
    var departureTime: String
    var stopID: String
    var stopSequence: Int

    var dwellSeconds: TimeInterval? {
        guard let arr = parseSeconds(arrivalTime),
              let dep = parseSeconds(departureTime) else { return nil }
        let diff = dep - arr
        return diff > 0 ? TimeInterval(diff) : nil
    }

    private func parseSeconds(_ hms: String) -> Int? {
        let parts = hms.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }
}

struct GTFSStop: Identifiable, Codable {
    var id: String
    var name: String
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
