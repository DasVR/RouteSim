import Foundation
import idevice
import Darwin

final class JITEnableContext {
    static let shared = JITEnableContext()

    private struct TunnelHandles {
        var adapter: OpaquePointer?
        var handshake: OpaquePointer?

        mutating func free() {
            if let handshake { rsd_handshake_free(handshake); self.handshake = nil }
            if let adapter   { adapter_free(adapter);         self.adapter = nil   }
        }
    }

    private var adapter: OpaquePointer?
    private var handshake: OpaquePointer?

    private let tunnelLock = NSLock()
    private var tunnelConnecting = false
    private var tunnelSemaphore: DispatchSemaphore?
    private var lastTunnelError: NSError?

    var adapterHandle: OpaquePointer?  { adapter }
    var handshakeHandle: OpaquePointer? { handshake }

    private init() {
        let logURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("idevice_log.txt")
        var path = Array(logURL.path.utf8CString)
        path.withUnsafeMutableBufferPointer { buffer in
            _ = idevice_init_logger(Info, Debug, buffer.baseAddress)
        }
    }

    deinit {
        if let handshake { rsd_handshake_free(handshake) }
        if let adapter   { adapter_free(adapter) }
    }

    // MARK: - Tunnel lifecycle

    func startTunnel() throws {
        tunnelLock.lock()
        if tunnelConnecting {
            let waiter = tunnelSemaphore
            tunnelLock.unlock()
            waiter?.wait()
            waiter?.signal()
            if let err = lastTunnelError { throw err }
            return
        }
        tunnelConnecting = true
        let sem = DispatchSemaphore(value: 0)
        tunnelSemaphore = sem
        tunnelLock.unlock()

        var finalError: NSError?
        defer {
            tunnelLock.lock()
            tunnelConnecting = false
            tunnelSemaphore = nil
            lastTunnelError = finalError
            tunnelLock.unlock()
            sem.signal()
        }

        do {
            let newTunnel = try createTunnel(hostname: "RouteSim")
            if let old = handshake { rsd_handshake_free(old) }
            if let old = adapter   { adapter_free(old) }
            adapter  = newTunnel.adapter
            handshake = newTunnel.handshake
        } catch let e as NSError {
            finalError = e
            throw e
        }
    }

    func ensureTunnel() throws {
        if adapter == nil || handshake == nil {
            try startTunnel()
        }
    }

    // MARK: - DDI helpers (used by mountDDI.swift / MountingProgress)

    func getMountedDeviceCount() throws -> Int {
        try withTunnelHandles { adapter, handshake in
            try withConnectedClient(
                adapter: adapter, handshake: handshake,
                connect: { image_mounter_connect_rsd(adapter, handshake, $0) },
                cleanup: { image_mounter_free($0) }
            ) { client in
                var devices: UnsafeMutablePointer<plist_t?>?
                var deviceCount = 0
                if let err = image_mounter_copy_devices(client, &devices, &deviceCount) {
                    throw makeFFIError(err, fallback: "Failed to fetch mounted devices")
                }
                if let devices {
                    for index in 0..<deviceCount {
                        if let device = devices[index] {
                            plist_free(device)
                        }
                    }
                    idevice_data_free(
                        UnsafeMutableRawPointer(devices).assumingMemoryBound(to: UInt8.self),
                        UInt(deviceCount * MemoryLayout<plist_t?>.stride)
                    )
                }
                return deviceCount
            }
        }
    }

    func mountPersonalDDI(
        withImagePath imagePath: String,
        trustcachePath: String,
        manifestPath: String
    ) throws {
        let imageData      = try mappedData(atPath: imagePath,      label: "developer disk image")
        let trustcacheData = try mappedData(atPath: trustcachePath, label: "trust cache")
        let manifestData   = try mappedData(atPath: manifestPath,   label: "manifest")

        try withTunnelHandles { adapter, handshake in
            let uniqueChipID: UInt64 = try withConnectedClient(
                adapter: adapter, handshake: handshake,
                connect: { lockdownd_connect_rsd(adapter, handshake, $0) },
                cleanup: { lockdownd_client_free($0) }
            ) { lockdown in
                var plist: plist_t?
                if let err = lockdownd_get_value(lockdown, "UniqueChipID", nil, &plist) {
                    throw makeFFIError(err, fallback: "Failed to query UniqueChipID")
                }
                defer {
                    if let plist { plist_free(plist) }
                }
                guard let plist else {
                    throw makeError("Failed to decode UniqueChipID")
                }
                var value: UInt64 = 0
                plist_get_uint_val(plist, &value)
                guard value != 0 else { throw makeError("Failed to decode UniqueChipID") }
                return value
            }

            try withConnectedClient(
                adapter: adapter, handshake: handshake,
                connect: { image_mounter_connect_rsd(adapter, handshake, $0) },
                cleanup: { image_mounter_free($0) }
            ) { mounter in
                let ffiError = imageData.withUnsafeBytes { imageBuf in
                    trustcacheData.withUnsafeBytes { tcBuf in
                        manifestData.withUnsafeBytes { mfBuf in
                            image_mounter_mount_personalized_with_callback_rsd(
                                mounter, adapter, handshake,
                                imageBuf.bindMemory(to: UInt8.self).baseAddress, imageData.count,
                                tcBuf.bindMemory(to: UInt8.self).baseAddress, trustcacheData.count,
                                mfBuf.bindMemory(to: UInt8.self).baseAddress, manifestData.count,
                                nil, uniqueChipID, progressCallback, nil
                            )
                        }
                    }
                }
                if let ffiError {
                    throw makeFFIError(ffiError, fallback: "Failed to mount personalized DDI")
                }
            }
        }
    }

    // MARK: - Private helpers

    private func createTunnel(hostname: String) throws -> TunnelHandles {
        let pairingFile = try getPairingFile()
        defer { rp_pairing_file_free(pairingFile) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(49152).bigEndian

        let deviceIP = DeviceConnectionContext.targetIPAddress
        guard deviceIP.withCString({ inet_pton(AF_INET, $0, &addr.sin_addr) }) == 1 else {
            throw makeError("Failed to parse target IP address.", code: -18)
        }

        var tunnel = TunnelHandles()
        let ffiError = hostname.withCString { hn in
            withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    tunnel_create_rppairing($0, socklen_t(MemoryLayout<sockaddr_in>.stride),
                        hn, pairingFile, nil, nil, &tunnel.adapter, &tunnel.handshake)
                }
            }
        }
        if let ffiError { throw makeFFIError(ffiError, fallback: "Failed to create tunnel") }
        guard tunnel.adapter != nil, tunnel.handshake != nil else {
            var t = tunnel; t.free()
            throw makeError("Tunnel created without valid handles")
        }
        return tunnel
    }

    private func getPairingFile() throws -> OpaquePointer {
        let url = PairingFileStore.prepareURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw makeError("Pairing file not found.", code: -17)
        }
        var handle: OpaquePointer?
        if let err = url.path.withCString({ rp_pairing_file_read($0, &handle) }) {
            throw makeFFIError(err, fallback: "Failed to read pairing file")
        }
        guard let handle else { throw makeError("Failed to read pairing file.", code: -17) }
        return handle
    }

    private func withTunnelHandles<T>(_ body: (OpaquePointer, OpaquePointer) throws -> T) throws -> T {
        try ensureTunnel()
        guard let a = adapter, let h = handshake else { throw makeError("Tunnel not connected") }
        return try body(a, h)
    }

    private func withConnectedClient<T>(
        adapter: OpaquePointer,
        handshake: OpaquePointer,
        connect: (UnsafeMutablePointer<OpaquePointer?>) -> UnsafeMutablePointer<IdeviceFfiError>?,
        cleanup: (OpaquePointer) -> Void,
        body: (OpaquePointer) throws -> T
    ) throws -> T {
        var client: OpaquePointer?
        if let err = connect(&client) {
            throw makeFFIError(err, fallback: "Failed to connect client")
        }
        guard let client else { throw makeError("Client handle was nil after connect") }
        defer { cleanup(client) }
        return try body(client)
    }

    private func makeError(_ message: String, code: Int = -1) -> NSError {
        NSError(domain: "RouteSim", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func makeFFIError(_ ptr: UnsafeMutablePointer<IdeviceFfiError>?, fallback: String) -> NSError {
        guard let ptr else { return makeError(fallback) }
        let msg = String(validatingUTF8: ptr.pointee.message ?? "") ?? fallback
        let code = Int(ptr.pointee.code)
        idevice_error_free(ptr)
        return makeError(msg, code: code)
    }

    private func mappedData(atPath path: String, label: String) throws -> Data {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe),
              !data.isEmpty else {
            throw makeError("\(label) file is missing or empty at \(path)")
        }
        return data
    }
}
