import CoreLocation

// MARK: - Route geometry utilities

enum RouteGeometry {

    // MARK: - Densification

    /// Subdivide a polyline so no step exceeds `maxStepMeters`.
    /// This ensures course and speed are smooth at 1 Hz playback.
    static func densify(
        _ coords: [CLLocationCoordinate2D],
        maxStepMeters: CLLocationDistance = 20
    ) -> [CLLocationCoordinate2D] {
        guard coords.count >= 2 else { return coords }
        var result: [CLLocationCoordinate2D] = [coords[0]]

        for (start, end) in zip(coords, coords.dropFirst()) {
            let dist = distance(from: start, to: end)
            guard dist > 0 else { continue }
            let steps = max(1, Int(ceil(dist / maxStepMeters)))
            for i in 1...steps {
                let f = Double(i) / Double(steps)
                result.append(interpolate(from: start, to: end, fraction: f))
            }
        }
        return result
    }

    // MARK: - Cumulative distances

    /// Returns an array of cumulative distances (metres) along `coords`.
    /// `result[0] == 0`; `result[i]` is the total distance to `coords[i]`.
    static func cumulativeDistances(_ coords: [CLLocationCoordinate2D]) -> [CLLocationDistance] {
        var result = [CLLocationDistance](repeating: 0, count: coords.count)
        for i in 1..<coords.count {
            result[i] = result[i - 1] + distance(from: coords[i - 1], to: coords[i])
        }
        return result
    }

    // MARK: - Position lookup

    /// Returns the interpolated coordinate and bearing at `odometer` metres along the route.
    static func position(
        at odometer: CLLocationDistance,
        coords: [CLLocationCoordinate2D],
        cumulative: [CLLocationDistance]
    ) -> (coordinate: CLLocationCoordinate2D, bearing: CLLocationDirection) {
        guard coords.count >= 2 else {
            return (coords.first ?? CLLocationCoordinate2D(), 0)
        }

        let total = cumulative.last ?? 0
        let clamped = min(max(odometer, 0), total)

        // Binary search for the segment containing `clamped`
        var lo = 0
        var hi = cumulative.count - 1
        while lo < hi - 1 {
            let mid = (lo + hi) / 2
            if cumulative[mid] <= clamped { lo = mid } else { hi = mid }
        }

        let segStart = cumulative[lo]
        let segEnd   = cumulative[hi]
        let segLen   = segEnd - segStart

        let fraction = segLen > 0 ? (clamped - segStart) / segLen : 0
        let coord = interpolate(from: coords[lo], to: coords[hi], fraction: fraction)
        let bear  = bearing(from: coords[lo], to: coords[hi])
        return (coord, bear)
    }

    // MARK: - Turn angle

    /// Returns the turn angle (0–180°) at vertex `index` in `coords`.
    static func turnAngle(at index: Int, coords: [CLLocationCoordinate2D]) -> Double {
        guard index > 0, index < coords.count - 1 else { return 0 }
        let b1 = bearing(from: coords[index - 1], to: coords[index])
        let b2 = bearing(from: coords[index],     to: coords[index + 1])
        let diff = abs(b2 - b1)
        return diff > 180 ? 360 - diff : diff
    }

    // MARK: - Bearing (forward azimuth)

    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> CLLocationDirection {
        let lat1 = a.latitude  * .pi / 180
        let lat2 = b.latitude  * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radians = atan2(y, x)
        return (radians * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    // MARK: - Helpers

    static func distance(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    static func interpolate(
        from a: CLLocationCoordinate2D,
        to b: CLLocationCoordinate2D,
        fraction: Double
    ) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude:  a.latitude  + (b.latitude  - a.latitude)  * fraction,
            longitude: a.longitude + (b.longitude - a.longitude) * fraction
        )
    }

    /// Total distance of a polyline in metres.
    static func totalDistance(_ coords: [CLLocationCoordinate2D]) -> CLLocationDistance {
        zip(coords, coords.dropFirst()).reduce(0) { $0 + distance(from: $1.0, to: $1.1) }
    }
}
