import Foundation
import CoreLocation
import Combine

// MARK: - Live stats published to the UI

struct RouteStats {
    var speedMps: Double = 0
    var speedMph: Double { speedMps * 2.23694 }
    var course: CLLocationDirection = 0
    var odometer: CLLocationDistance = 0
    var totalDistance: CLLocationDistance = 0
    var elapsed: TimeInterval = 0
    var progress: Double = 0        // 0–1
    var eta: TimeInterval = 0       // seconds remaining at current speed
}

// MARK: - RoutePlayer
//
// Fixed-cadence (1 Hz wall-clock) location player.
// Uses a DispatchSourceTimer so there is no drift from accumulated Task.sleep delays.
//
// Speed and course are NOT sent to the device (the FFI only accepts lat/lon).
// They are computed here for the HUD and to drive the dynamics model — CoreLocation
// derives speed/course from the rate of change between successive injected fixes.

@MainActor
final class RoutePlayer: ObservableObject {

    // MARK: - Inputs (set before calling prepare())
    var waypoints: [CLLocationCoordinate2D] = []
    var profile: MovementProfile = .drive
    var speedMultiplier: Double = 1.0   // 0.5–10x
    var loop: Bool = false

    // MARK: - State
    @Published private(set) var isPlaying = false
    @Published private(set) var isPreparing = false
    @Published private(set) var stats = RouteStats()
    @Published private(set) var currentCoordinate: CLLocationCoordinate2D?
    @Published private(set) var prepareError: String?

    // MARK: - Tick configuration
    private let tickInterval: TimeInterval = 1.0

    // MARK: - Prepared route data
    private var densified: [CLLocationCoordinate2D] = []
    private var cumulative: [CLLocationDistance] = []
    private var segmentSpeeds: [CLLocationSpeed] = []   // one per densified segment
    private var busAnchors: [BusStopAnchor] = []
    private var busStopStartTimes: [Int: TimeInterval] = [:]

    // MARK: - Playback state
    private var odometer: CLLocationDistance = 0
    private var currentSpeed: CLLocationSpeed = 0
    private var elapsedTime: TimeInterval = 0
    private var tickSource: DispatchSourceTimer?

    // MARK: - OSM speed limit cache (keyed by route hash)
    private var osmSpeedCache: [String: [CLLocationSpeed]] = [:]

    private let simulator = LocationSimulator.shared

    // MARK: - Prepare

    func prepare() async {
        guard !waypoints.isEmpty else { return }
        isPreparing = true
        prepareError = nil

        let densified = RouteGeometry.densify(waypoints, maxStepMeters: maxStepMeters())
        let cumulative = RouteGeometry.cumulativeDistances(densified)
        let total = cumulative.last ?? 0

        var speeds: [CLLocationSpeed]
        if profile.useRoadSpeedLimits {
            speeds = await fetchOSMSpeeds(for: densified, fallback: profile.cruiseSpeed)
        } else {
            speeds = [CLLocationSpeed](repeating: profile.cruiseSpeed, count: max(1, densified.count - 1))
        }

        // Pre-compute turn-aware target speeds: reduce at upcoming sharp turns
        for i in 0..<speeds.count {
            let angle = RouteGeometry.turnAngle(at: i + 1, coords: densified)
            speeds[i] = DrivingDynamics.turnTargetSpeed(
                baseCruise: speeds[i],
                upcomingTurnAngle: angle,
                factor: profile.turnSlowdownFactor
            )
            if profile.mode == .drive {
                speeds[i] = max(speeds[i], DrivingDynamics.minimumDrivingSpeedMps)
            }
        }

        var anchors: [BusStopAnchor] = []
        // Bus anchors will be populated when RouteStore provides RouteStop data.
        // For now the player supports pure waypoint routes; stops injected separately.

        await MainActor.run {
            self.densified   = densified
            self.cumulative  = cumulative
            self.segmentSpeeds = speeds
            self.busAnchors  = anchors
            self.odometer    = 0
            self.currentSpeed = 0
            self.elapsedTime = 0
            self.busStopStartTimes = [:]
            self.stats = RouteStats(totalDistance: total)
            self.isPreparing = false
        }
    }

    // MARK: - Playback controls

    func play() {
        guard !densified.isEmpty, !isPlaying else { return }
        isPlaying = true
        simulator.stopHold()
        startTick()
    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        stopTick()
        if let coord = currentCoordinate {
            simulator.startHold(at: coord)
        }
    }

    func stop() {
        isPlaying = false
        stopTick()
        simulator.clear()
        odometer = 0
        currentSpeed = 0
        elapsedTime = 0
        busStopStartTimes = [:]
        currentCoordinate = nil
        stats = RouteStats(totalDistance: cumulative.last ?? 0)
    }

    func scrub(to progress: Double) {
        let total = cumulative.last ?? 0
        guard total > 0 else { return }
        odometer = min(max(progress, 0), 1) * total
        let (coord, bearing) = RouteGeometry.position(
            at: odometer, coords: densified, cumulative: cumulative)
        currentCoordinate = coord
        if !isPlaying {
            simulator.startHold(at: coord)
        }
        updateStats(speed: currentSpeed, bearing: bearing)
    }

    // MARK: - Inject bus stops (called by SimulateViewModel after GTFSService resolves)

    func setBusAnchors(_ anchors: [BusStopAnchor]) {
        busAnchors = anchors
        busStopStartTimes = [:]
    }

    // MARK: - Private tick engine

    private func startTick() {
        stopTick()
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + tickInterval, repeating: tickInterval, leeway: .milliseconds(50))
        source.setEventHandler { [weak self] in
            self?.tick()
        }
        source.resume()
        tickSource = source
    }

    private func stopTick() {
        tickSource?.cancel()
        tickSource = nil
    }

    private func tick() {
        guard isPlaying, !densified.isEmpty else { return }

        let total = cumulative.last ?? 0
        guard total > 0 else { stop(); return }

        let scaledDt = tickInterval * speedMultiplier
        elapsedTime += tickInterval

        // Bus dwell check
        var dwelling = false
        if profile.mode == .bus, !busAnchors.isEmpty {
            let result = BusDwell.activeDwell(
                odometer: odometer,
                elapsed: elapsedTime,
                stopStartTimes: &busStopStartTimes,
                anchors: busAnchors
            )
            dwelling = result.isDwelling
        }

        // Target speed for this segment
        let segIndex = min(segmentIndex(at: odometer), segmentSpeeds.count - 1)
        let rawTarget = segIndex >= 0 ? segmentSpeeds[segIndex] : profile.cruiseSpeed
        let targetSpeed: CLLocationSpeed = dwelling ? 0 : min(rawTarget, profile.maxSpeed)

        // Ramp speed
        currentSpeed = DrivingDynamics.nextSpeed(
            current: currentSpeed,
            target: targetSpeed,
            acceleration: profile.acceleration,
            braking: profile.braking,
            dt: scaledDt
        )
        currentSpeed = DrivingDynamics.applyJitter(speed: currentSpeed, jitter: profile.speedJitter)

        // Advance odometer (paused at dwell = don't move)
        if !dwelling {
            odometer += currentSpeed * scaledDt
        }

        // End of route
        if odometer >= total {
            odometer = total
            let (coord, bearing) = RouteGeometry.position(
                at: odometer, coords: densified, cumulative: cumulative)
            currentCoordinate = coord
            updateStats(speed: currentSpeed, bearing: bearing)
            Task { _ = await simulator.setLocation(coord) }

            if loop {
                odometer = 0
                currentSpeed = 0
                busStopStartTimes = [:]
            } else {
                isPlaying = false
                stopTick()
                simulator.startHold(at: coord)
            }
            return
        }

        let (coord, bearing) = RouteGeometry.position(
            at: odometer, coords: densified, cumulative: cumulative)
        currentCoordinate = coord
        updateStats(speed: currentSpeed, bearing: bearing)
        Task { _ = await simulator.setLocation(coord) }
    }

    private func updateStats(speed: CLLocationSpeed, bearing: CLLocationDirection) {
        let total = cumulative.last ?? 1
        let prog  = total > 0 ? min(odometer / total, 1.0) : 0
        let remaining = total - odometer
        let eta = speed > 0 ? remaining / (speed * speedMultiplier) : 0

        stats = RouteStats(
            speedMps: speed,
            course: bearing,
            odometer: odometer,
            totalDistance: total,
            elapsed: elapsedTime,
            progress: prog,
            eta: eta
        )
    }

    private func segmentIndex(at odo: CLLocationDistance) -> Int {
        guard cumulative.count >= 2 else { return 0 }
        var lo = 0, hi = cumulative.count - 2
        while lo < hi {
            let mid = (lo + hi) / 2
            if cumulative[mid + 1] < odo { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    private func maxStepMeters() -> CLLocationDistance {
        // At 1 Hz, max step = max speed in m/s (no teleport jumps)
        return profile.maxSpeed * tickInterval
    }

    // MARK: - OSM speed limit prefetch

    private func fetchOSMSpeeds(
        for coords: [CLLocationCoordinate2D],
        fallback: CLLocationSpeed
    ) async -> [CLLocationSpeed] {
        guard coords.count >= 2 else { return [fallback] }
        let count = coords.count - 1
        let fallbacks = [CLLocationSpeed](repeating: fallback, count: count)

        // Use OSM Overpass API (same approach as original MapSelectionView)
        guard let query = overpassQuery(for: coords) else { return fallbacks }
        guard let url = URL(string: "https://overpass-api.de/api/interpreter") else { return fallbacks }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data(query.utf8)
        request.timeoutInterval = 15

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = json["elements"] as? [[String: Any]] else {
            return fallbacks
        }

        let ways = elements.compactMap { el -> (geometry: [CLLocationCoordinate2D], speed: CLLocationSpeed)? in
            guard let tags = el["tags"] as? [String: String],
                  let rawSpeed = tags["maxspeed"] ?? tags["maxspeed:forward"],
                  let speed = parseOSMSpeed(rawSpeed),
                  let geom = el["geometry"] as? [[String: Double]] else { return nil }
            let pts = geom.compactMap { d -> CLLocationCoordinate2D? in
                guard let lat = d["lat"], let lon = d["lon"] else { return nil }
                return CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
            return (pts, speed)
        }

        var speeds = fallbacks
        for i in 0..<count {
            let mid = RouteGeometry.interpolate(from: coords[i], to: coords[i+1], fraction: 0.5)
            if let best = ways.min(by: {
                RouteGeometry.distance(from: $0.geometry.first ?? mid, to: mid) <
                RouteGeometry.distance(from: $1.geometry.first ?? mid, to: mid)
            }) {
                speeds[i] = best.speed
            }
        }
        return speeds
    }

    private func overpassQuery(for coords: [CLLocationCoordinate2D]) -> String? {
        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return nil }
        let pad = 0.002
        let bbox = "\(minLat - pad),\(minLon - pad),\(maxLat + pad),\(maxLon + pad)"
        return """
        [out:json][timeout:15];
        (
          way(\(bbox))[highway][maxspeed];
          way(\(bbox))[highway]["maxspeed:forward"];
        );
        out geom;
        """
    }

    private func parseOSMSpeed(_ raw: String) -> CLLocationSpeed? {
        if let kmh = Double(raw) { return kmh / 3.6 }
        if raw.hasSuffix(" mph"), let mph = Double(raw.dropLast(4)) { return mph * 0.44704 }
        let known: [String: CLLocationSpeed] = [
            "RU:urban": 60/3.6, "RU:rural": 90/3.6,
            "US:urban": 25*0.44704, "US:rural": 55*0.44704,
        ]
        return known[raw]
    }
}
