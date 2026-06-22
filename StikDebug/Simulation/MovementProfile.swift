import CoreLocation

// MARK: - Movement mode

enum MovementMode: String, Codable, CaseIterable, Identifiable {
    case walk
    case bike
    case drive
    case bus
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .walk:   return "Walk"
        case .bike:   return "Bike"
        case .drive:  return "Drive"
        case .bus:    return "Bus"
        case .custom: return "Custom"
        }
    }

    var systemImage: String {
        switch self {
        case .walk:   return "figure.walk"
        case .bike:   return "bicycle"
        case .drive:  return "car.fill"
        case .bus:    return "bus.fill"
        case .custom: return "slider.horizontal.3"
        }
    }
}

// MARK: - Movement profile

struct MovementProfile: Codable {
    var mode: MovementMode

    /// Target speed on open segments (m/s)
    var cruiseSpeed: CLLocationSpeed
    /// Absolute maximum speed allowed (m/s)
    var maxSpeed: CLLocationSpeed
    /// Acceleration (m/s²) — positive
    var acceleration: Double
    /// Braking deceleration (m/s²) — positive magnitude
    var braking: Double
    /// Fraction of cruise speed kept through a sharp turn (0–1)
    var turnSlowdownFactor: Double
    /// Random speed jitter ±fraction applied each tick (0–1)
    var speedJitter: Double
    /// Whether to fetch OSM speed limits for this mode
    var useRoadSpeedLimits: Bool
    /// Dwell time range at each bus stop (seconds).  Nil for non-bus modes.
    var stopDwellRange: ClosedRange<TimeInterval>?
    /// For Custom mode: the user-specified constant speed in m/s
    var customSpeedMps: CLLocationSpeed

    // MARK: - Factory defaults

    static let walk = MovementProfile(
        mode: .walk,
        cruiseSpeed: 1.4,
        maxSpeed: 2.5,
        acceleration: 0.5,
        braking: 0.8,
        turnSlowdownFactor: 0.9,
        speedJitter: 0.05,
        useRoadSpeedLimits: false,
        stopDwellRange: nil,
        customSpeedMps: 1.4
    )

    static let bike = MovementProfile(
        mode: .bike,
        cruiseSpeed: 5.0,
        maxSpeed: 8.0,
        acceleration: 1.0,
        braking: 1.5,
        turnSlowdownFactor: 0.7,
        speedJitter: 0.08,
        useRoadSpeedLimits: false,
        stopDwellRange: nil,
        customSpeedMps: 5.0
    )

    // Drive is tuned for Life360 driving detection.
    // Requirements:
    //   • Cadence: strict 1 Hz (one fix/second) at 1× speed multiplier
    //   • Cruise: 13.4–18 m/s (30–40 mph) — never drops below 8 m/s (17 mph)
    //   • Ramp: 2.0 m/s² accel (0→30 mph in ~6s), 2.5 m/s² brake into turns
    //   • Jitter: ±4% so the speed isn't robotically constant
    //   • OSM speed limits used to adapt to road context
    //
    // CORE MOTION LIMITATION (cannot be fixed):
    //   Life360 also fuses accelerometer/gyroscope activity (Core Motion) for
    //   driving classification. The DVT location simulation service does NOT
    //   inject Core Motion data — only GPS position is affected.
    //   We optimise everything on the GPS side (speed, course, cadence) but
    //   cannot guarantee motion-coprocessor signals will match.
    //   Surface this fact in UI when users ask why Life360 occasionally
    //   shows "not driving" despite correct GPS speed.
    static let drive = MovementProfile(
        mode: .drive,
        cruiseSpeed: 13.4,   // 30 mph
        maxSpeed: 22.4,      // 50 mph
        acceleration: 2.0,   // ~6s ramp to cruise
        braking: 2.5,        // realistic brake into turns/stops
        turnSlowdownFactor: 0.5,
        speedJitter: 0.04,   // ±4% per tick
        useRoadSpeedLimits: true,
        stopDwellRange: nil,
        customSpeedMps: 13.4
    )

    static let bus = MovementProfile(
        mode: .bus,
        cruiseSpeed: 9.0,    // ~20 mph
        maxSpeed: 13.4,      // 30 mph
        acceleration: 1.2,
        braking: 1.8,
        turnSlowdownFactor: 0.6,
        speedJitter: 0.04,
        useRoadSpeedLimits: true,
        stopDwellRange: 15...45,
        customSpeedMps: 9.0
    )

    static func custom(speedMps: CLLocationSpeed) -> MovementProfile {
        MovementProfile(
            mode: .custom,
            cruiseSpeed: speedMps,
            maxSpeed: speedMps * 1.1,
            acceleration: 1.0,
            braking: 1.5,
            turnSlowdownFactor: 0.8,
            speedJitter: 0.02,
            useRoadSpeedLimits: false,
            stopDwellRange: nil,
            customSpeedMps: speedMps
        )
    }

    static func `default`(for mode: MovementMode) -> MovementProfile {
        switch mode {
        case .walk:   return .walk
        case .bike:   return .bike
        case .drive:  return .drive
        case .bus:    return .bus
        case .custom: return .custom(speedMps: 5.0)
        }
    }
}
