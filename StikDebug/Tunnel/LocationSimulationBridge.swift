import Foundation
import idevice
import Darwin

// MARK: - Status codes returned by simulate_location / clear_simulated_location

enum LocationSimulationStatus {
    static let ok: Int32 = 0
    static let invalidIP: Int32 = 1
    static let pairingRead: Int32 = 2
    static let providerCreate: Int32 = 3
    static let remoteServer: Int32 = 9
    static let locationSimulation: Int32 = 10
    static let locationSet: Int32 = 11
    static let locationClear: Int32 = 12
}

// MARK: - Cached RSD session state (one persistent connection reused each tick)

private enum LocationSimulationState {
    static var adapter: OpaquePointer?
    static var handshake: OpaquePointer?
    static var remoteServer: OpaquePointer?
    static var locationSimulation: OpaquePointer?

    static func cleanup() {
        if let locationSimulation {
            location_simulation_free(locationSimulation)
            self.locationSimulation = nil
        }
        if let remoteServer {
            remote_server_free(remoteServer)
            self.remoteServer = nil
        }
        if let handshake {
            rsd_handshake_free(handshake)
            self.handshake = nil
        }
        if let adapter {
            adapter_free(adapter)
            self.adapter = nil
        }
    }
}

// MARK: - Serial dispatch queue (all C bridge calls must be on this queue)

enum LocationSimulationCommandQueue {
    static let shared = DispatchQueue(label: "com.stik.routesim.location-sim", qos: .userInitiated)
}

// MARK: - Core injection function
//
// Returns LocationSimulationStatus.ok (0) on success.
// Fast path: reuses the cached RSD session for every tick.
// Slow path: opens a fresh tunnel_create_rppairing → remote_server_connect_rsd →
//            location_simulation_new chain on first call or after a broken session.
//
// IMPORTANT: lat/lon only — speed, course, and horizontalAccuracy are derived by
// CoreLocation from the rate of change between successive injected fixes.
// All realism is achieved by how frequently and how far apart you call this.

func simulate_location(
    _ deviceIP: String,
    _ latitude: Double,
    _ longitude: Double,
    _ pairingFile: String
) -> Int32 {
    // Fast path: reuse cached session
    if let locationSimulation = LocationSimulationState.locationSimulation {
        if let ffiError = location_simulation_set(locationSimulation, latitude, longitude) {
            idevice_error_free(ffiError)
            LocationSimulationState.cleanup()
            // fall through to slow path (reconnect)
        } else {
            return LocationSimulationStatus.ok
        }
    }

    // Slow path: build a fresh RSD tunnel
    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(49152).bigEndian

    let inetResult = deviceIP.withCString { inet_pton(AF_INET, $0, &address.sin_addr) }
    guard inetResult == 1 else {
        return LocationSimulationStatus.invalidIP
    }

    var pairingHandle: OpaquePointer?
    if let pairingError = pairingFile.withCString({ rp_pairing_file_read($0, &pairingHandle) }) {
        idevice_error_free(pairingError)
        return LocationSimulationStatus.pairingRead
    }
    guard let pairingHandle else {
        return LocationSimulationStatus.pairingRead
    }
    defer { rp_pairing_file_free(pairingHandle) }

    let providerError = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            tunnel_create_rppairing(
                $0,
                socklen_t(MemoryLayout<sockaddr_in>.stride),
                "RouteSimLocation",
                pairingHandle,
                nil,
                nil,
                &LocationSimulationState.adapter,
                &LocationSimulationState.handshake
            )
        }
    }
    if let providerError {
        idevice_error_free(providerError)
        LocationSimulationState.cleanup()
        return LocationSimulationStatus.providerCreate
    }

    let remoteServerError = remote_server_connect_rsd(
        LocationSimulationState.adapter,
        LocationSimulationState.handshake,
        &LocationSimulationState.remoteServer
    )
    if let remoteServerError {
        idevice_error_free(remoteServerError)
        LocationSimulationState.cleanup()
        return LocationSimulationStatus.remoteServer
    }

    let locationSimulationError = location_simulation_new(
        LocationSimulationState.remoteServer,
        &LocationSimulationState.locationSimulation
    )
    if let locationSimulationError {
        idevice_error_free(locationSimulationError)
        LocationSimulationState.cleanup()
        return LocationSimulationStatus.locationSimulation
    }
    // Ownership of remoteServer transferred to locationSimulation
    LocationSimulationState.remoteServer = nil

    let locationSetError = location_simulation_set(
        LocationSimulationState.locationSimulation,
        latitude,
        longitude
    )
    if let locationSetError {
        idevice_error_free(locationSetError)
        LocationSimulationState.cleanup()
        return LocationSimulationStatus.locationSet
    }

    return LocationSimulationStatus.ok
}

// MARK: - Clear (stop spoofing, return device to real GPS)

func clear_simulated_location() -> Int32 {
    guard let locationSimulation = LocationSimulationState.locationSimulation else {
        return LocationSimulationStatus.locationClear
    }
    let ffiError = location_simulation_clear(locationSimulation)
    LocationSimulationState.cleanup()
    if let ffiError {
        idevice_error_free(ffiError)
        return LocationSimulationStatus.locationClear
    }
    return LocationSimulationStatus.ok
}
