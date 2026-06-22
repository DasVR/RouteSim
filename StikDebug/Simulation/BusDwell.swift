import CoreLocation

// MARK: - Bus stop dwell model

struct BusStopAnchor {
    /// Odometer distance (metres from route start) at which this stop begins
    let odometer: CLLocationDistance
    /// Coordinate of the stop (for keep-alive while dwelling)
    let coordinate: CLLocationCoordinate2D
    /// Dwell duration (seconds) at this stop
    let dwell: TimeInterval
    /// Name for display (from GTFS stop_name or user tap)
    let name: String
}

enum BusDwell {

    // MARK: - Build stop anchors from route stops + odometer map

    static func anchors(
        from stops: [RouteStop],
        coords: [CLLocationCoordinate2D],
        cumulative: [CLLocationDistance],
        dwellRange: ClosedRange<TimeInterval>
    ) -> [BusStopAnchor] {
        stops.map { stop in
            let anchor = nearestOdometer(to: stop.coordinate, coords: coords, cumulative: cumulative)
            let dwell: TimeInterval
            if let gtfsDwell = stop.scheduledDwellSeconds {
                dwell = max(5, gtfsDwell)
            } else {
                dwell = TimeInterval.random(in: dwellRange)
            }
            return BusStopAnchor(
                odometer: anchor,
                coordinate: stop.coordinate,
                dwell: dwell,
                name: stop.name
            )
        }
    }

    // MARK: - Active dwell query

    /// Returns the remaining dwell seconds if `odometer` is within a stop's approach zone.
    /// `approachMeters` defines how far before the stop the player starts braking.
    static func activeDwell(
        odometer: CLLocationDistance,
        elapsed: TimeInterval,
        stopStartTimes: inout [Int: TimeInterval],
        anchors: [BusStopAnchor],
        approachMeters: CLLocationDistance = 30
    ) -> (isDwelling: Bool, stopIndex: Int?, remainingDwell: TimeInterval) {
        for (i, anchor) in anchors.enumerated() {
            let dist = abs(odometer - anchor.odometer)
            if dist <= approachMeters {
                if stopStartTimes[i] == nil {
                    stopStartTimes[i] = elapsed
                }
                let timeAtStop = elapsed - (stopStartTimes[i] ?? elapsed)
                if timeAtStop < anchor.dwell {
                    return (true, i, anchor.dwell - timeAtStop)
                }
            }
        }
        return (false, nil, 0)
    }

    // MARK: - Helpers

    private static func nearestOdometer(
        to target: CLLocationCoordinate2D,
        coords: [CLLocationCoordinate2D],
        cumulative: [CLLocationDistance]
    ) -> CLLocationDistance {
        var best: (odo: CLLocationDistance, dist: CLLocationDistance) = (0, .greatestFiniteMagnitude)
        for (i, coord) in coords.enumerated() {
            let d = RouteGeometry.distance(from: coord, to: target)
            if d < best.dist {
                best = (cumulative[i], d)
            }
        }
        return best.odo
    }
}
