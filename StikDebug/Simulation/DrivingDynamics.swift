import CoreLocation

// MARK: - Pure movement dynamics (no state, no side effects)

enum DrivingDynamics {

    // MARK: - Speed ramping

    /// Step speed toward `target` using acceleration or braking, scaled by `dt`.
    static func nextSpeed(
        current: CLLocationSpeed,
        target: CLLocationSpeed,
        acceleration: Double,
        braking: Double,
        dt: TimeInterval
    ) -> CLLocationSpeed {
        if current < target {
            return min(current + acceleration * dt, target)
        } else if current > target {
            return max(current - braking * dt, target)
        }
        return current
    }

    // MARK: - Turn speed reduction

    /// Reduce cruise speed for an upcoming turn.
    /// Sharp turns (angle ≥ 90°) reduce to `factor * cruise`; gradual turns are proportional.
    static func turnTargetSpeed(
        baseCruise: CLLocationSpeed,
        upcomingTurnAngle: Double,
        factor: Double
    ) -> CLLocationSpeed {
        guard upcomingTurnAngle > 15 else { return baseCruise }
        let normalized = min(upcomingTurnAngle / 90.0, 1.0)
        let reduction  = 1.0 - (1.0 - factor) * normalized
        return baseCruise * reduction
    }

    // MARK: - Jitter

    /// Apply random noise ±`jitterFraction` to `speed` so motion doesn't look robotic.
    static func applyJitter(speed: CLLocationSpeed, jitter: Double) -> CLLocationSpeed {
        guard jitter > 0, speed > 0 else { return speed }
        let delta = speed * jitter * Double.random(in: -1...1)
        return max(0, speed + delta)
    }

    // MARK: - Life360 driving detection helpers

    /// Returns true if the speed is in the range Life360 typically classifies as driving.
    /// Life360 threshold is approximately 7 m/s (15 mph); we target ≥ 8 m/s for headroom.
    static func isDrivingSpeed(_ speedMps: CLLocationSpeed) -> Bool {
        speedMps >= 7.0
    }

    /// Minimum safe cruise speed for the Drive profile so Life360 reliably detects driving.
    static let minimumDrivingSpeedMps: CLLocationSpeed = 8.0
}
