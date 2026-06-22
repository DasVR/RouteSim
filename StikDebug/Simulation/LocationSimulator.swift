import Foundation
import CoreLocation

// MARK: - Typed error wrapper around the C bridge's Int32 status codes

enum LocationSimulatorError: LocalizedError {
    case invalidIP
    case pairingFileUnreadable
    case providerCreateFailed
    case remoteServerFailed
    case sessionCreateFailed
    case locationSetFailed
    case clearFailed
    case unknown(Int32)

    init(statusCode: Int32) {
        switch statusCode {
        case LocationSimulationStatus.invalidIP:          self = .invalidIP
        case LocationSimulationStatus.pairingRead:        self = .pairingFileUnreadable
        case LocationSimulationStatus.providerCreate:     self = .providerCreateFailed
        case LocationSimulationStatus.remoteServer:       self = .remoteServerFailed
        case LocationSimulationStatus.locationSimulation: self = .sessionCreateFailed
        case LocationSimulationStatus.locationSet:        self = .locationSetFailed
        case LocationSimulationStatus.locationClear:      self = .clearFailed
        default:                                          self = .unknown(statusCode)
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidIP:              return "Device IP address is invalid. Check Settings."
        case .pairingFileUnreadable:  return "Pairing file is missing or unreadable. Re-import it."
        case .providerCreateFailed:   return "Could not create the RSD tunnel. Is LocalDevVPN connected?"
        case .remoteServerFailed:     return "Remote server connection failed. Wake the device and try again."
        case .sessionCreateFailed:    return "Location simulation session could not be created."
        case .locationSetFailed:      return "Failed to set the simulated location. Session was reset."
        case .clearFailed:            return "Failed to clear the simulated location."
        case .unknown(let code):      return "Location simulation error (code \(code))."
        }
    }
}

// MARK: - LocationSimulator
//
// Thread-safe wrapper over the C bridge.
// All bridge calls are dispatched on LocationSimulationCommandQueue.shared (serial).

final class LocationSimulator: ObservableObject {
    static let shared = LocationSimulator()

    @Published private(set) var isHolding = false
    @Published private(set) var lastError: LocationSimulatorError?

    private var holdTimer: Timer?
    private var holdCoordinate: CLLocationCoordinate2D?

    private init() {}

    // MARK: - Set location (called each tick by RoutePlayer)

    @discardableResult
    func setLocation(_ coordinate: CLLocationCoordinate2D) async -> Result<Void, LocationSimulatorError> {
        await withCheckedContinuation { continuation in
            LocationSimulationCommandQueue.shared.async {
                let code = simulate_location(
                    DeviceConnectionContext.targetIPAddress,
                    coordinate.latitude,
                    coordinate.longitude,
                    PairingFileStore.prepareURL().path
                )
                if code == LocationSimulationStatus.ok {
                    continuation.resume(returning: .success(()))
                } else {
                    let error = LocationSimulatorError(statusCode: code)
                    Task { @MainActor in self.lastError = error }
                    continuation.resume(returning: .failure(error))
                }
            }
        }
    }

    // MARK: - Clear

    func clear() {
        LocationSimulationCommandQueue.shared.async {
            _ = clear_simulated_location()
        }
        stopHold()
    }

    // MARK: - Hold / keep-alive
    //
    // Keeps re-sending the last coordinate every 4 seconds so iOS does not
    // revert to the real GPS while the player is paused or at end-of-route.

    func startHold(at coordinate: CLLocationCoordinate2D) {
        stopHold()
        holdCoordinate = coordinate
        isHolding = true

        DispatchQueue.main.async {
            self.holdTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
                guard let self, let coord = self.holdCoordinate else { return }
                LocationSimulationCommandQueue.shared.async {
                    _ = simulate_location(
                        DeviceConnectionContext.targetIPAddress,
                        coord.latitude, coord.longitude,
                        PairingFileStore.prepareURL().path
                    )
                }
            }
        }
    }

    func stopHold() {
        DispatchQueue.main.async {
            self.holdTimer?.invalidate()
            self.holdTimer = nil
            self.isHolding = false
            self.holdCoordinate = nil
        }
    }
}
