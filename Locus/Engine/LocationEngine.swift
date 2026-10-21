import CoreLocation
import Foundation
import idevice

enum LocationEngineError: LocalizedError {
    case invalidIP
    case invalidCoordinate
    case pairingRead(String?)
    case tunnelCreate(String?)
    case remoteServer(String?)
    case simulationCreate(String?)
    case locationSet(String?)
    case locationClear(String?)
    case notActive

    var errorDescription: String? {
        switch self {
        case .invalidIP:
            return "穿隧 IP 無效，請到「設定」檢查 Device IP（預設為 10.7.0.1）。"
        case .invalidCoordinate:
            return "座標超出有效範圍，已取消這次定位操作。"
        case .pairingRead(let detail):
            return "無法讀取 RPPairing 檔案，請用 idevice_pair 以 RPPairing 模式重新產生一份。\(Self.suffix(detail))"
        case .tunnelCreate(let detail):
            return "無法連線到裝置端的開發者穿隧通道。請確認「設定」裡的 Device IP 對應的是 LocalDevVPN 顯示的「Device IP」（不是「Tunnel IP」），並確認 LocalDevVPN 已連線。\(Self.suffix(detail))"
        case .remoteServer(let detail):
            return "已連上穿隧通道，但 RemoteXPC 交握失敗。\(Self.suffix(detail))"
        case .simulationCreate(let detail):
            return "無法開啟 Apple 的定位模擬服務。\(Self.suffix(detail))"
        case .locationSet(let detail):
            return "設定模擬座標失敗。\(Self.suffix(detail))"
        case .locationClear(let detail):
            return "清除模擬定位失敗。\(Self.suffix(detail))"
        case .notActive:
            return "目前沒有進行中的模擬連線。"
        }
    }

    private static func suffix(_ detail: String?) -> String {
        guard let detail, !detail.isEmpty else { return "" }
        return "（\(detail)）"
    }
}

/// Thin Swift wrapper around idevice’s DVT location simulation (injects into locationd).
enum LocationEngine {
    private static let queue = DispatchQueue(label: "com.chrismack.locus.location", qos: .userInitiated)

    private static var adapter: OpaquePointer?
    private static var handshake: OpaquePointer?
    private static var remoteServer: OpaquePointer?
    private static var locationSimulation: OpaquePointer?

    static var isSessionActive: Bool {
        queue.sync { locationSimulation != nil }
    }

    static func set(latitude: Double, longitude: Double, pairingPath: String, deviceIP: String) -> Result<Void, LocationEngineError> {
        var result: Result<Void, LocationEngineError> = .failure(.locationSet(nil))
        queue.sync {
            if let error = setLocked(latitude: latitude, longitude: longitude, pairingPath: pairingPath, deviceIP: deviceIP) {
                result = .failure(error)
            } else {
                result = .success(())
            }
        }
        return result
    }

    static func clear() -> Result<Void, LocationEngineError> {
        var result: Result<Void, LocationEngineError> = .failure(.notActive)
        queue.sync {
            if let error = clearLocked() {
                result = .failure(error)
            } else {
                result = .success(())
            }
        }
        return result
    }

    private static func cleanup() {
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

    /// Reads code/sub_code/message off a raw FFI error before it's freed, so the
    /// real failure reason reaches the Xcode console instead of being discarded.
    /// Never pass pairing credentials/keys through here — only protocol-level detail.
    private static func describe(_ error: UnsafeMutablePointer<IdeviceFfiError>) -> String {
        let code = error.pointee.code
        let subCode = error.pointee.sub_code
        let message = error.pointee.message.map { String(cString: $0) } ?? "<no message>"
        return "code=\(code) sub_code=\(subCode) message=\(message)"
    }

    private static func setLocked(latitude: Double, longitude: Double, pairingPath: String, deviceIP: String) -> LocationEngineError? {
        NSLog("[Locus] LocationEngine.set targetDeviceIP=%@ lat=%.5f lon=%.5f", deviceIP, latitude, longitude)

        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard latitude.isFinite, longitude.isFinite, CLLocationCoordinate2DIsValid(coordinate) else {
            return .invalidCoordinate
        }

        if let locationSimulation {
            if let err = location_simulation_set(locationSimulation, latitude, longitude) {
                let detail = describe(err)
                NSLog("[Locus] location_simulation_set (reuse) failed: %@ — rebuilding tunnel", detail)
                idevice_error_free(err)
                cleanup()
            } else {
                NSLog("[Locus] location_simulation_set (reuse) ok")
                return nil
            }
        }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(49152).bigEndian
        let inetResult = deviceIP.withCString { inet_pton(AF_INET, $0, &address.sin_addr) }
        guard inetResult == 1 else {
            NSLog("[Locus] invalid device IP: %@", deviceIP)
            return .invalidIP
        }

        var pairingHandle: OpaquePointer?
        if let pairingError = pairingPath.withCString({ rp_pairing_file_read($0, &pairingHandle) }) {
            let detail = describe(pairingError)
            NSLog("[Locus] rp_pairing_file_read failed at %@: %@", pairingPath, detail)
            idevice_error_free(pairingError)
            return .pairingRead(detail)
        }
        guard let pairingHandle else {
            NSLog("[Locus] rp_pairing_file_read returned no handle and no error")
            return .pairingRead(nil)
        }
        defer { rp_pairing_file_free(pairingHandle) }
        NSLog("[Locus] RPPairing file read ok from %@", pairingPath)

        let providerError = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                tunnel_create_rppairing(
                    $0,
                    socklen_t(MemoryLayout<sockaddr_in>.stride),
                    "LocusLocation",
                    pairingHandle,
                    nil,
                    nil,
                    &adapter,
                    &handshake
                )
            }
        }
        if let providerError {
            let detail = describe(providerError)
            NSLog("[Locus] tunnel_create_rppairing failed dialing %@:49152 — %@", deviceIP, detail)
            idevice_error_free(providerError)
            cleanup()
            return .tunnelCreate(detail)
        }
        NSLog("[Locus] tunnel_create_rppairing ok (adapter + RSD handshake established) dialing %@:49152", deviceIP)

        if let remoteServerError = remote_server_connect_rsd(adapter, handshake, &remoteServer) {
            let detail = describe(remoteServerError)
            NSLog("[Locus] remote_server_connect_rsd failed: %@", detail)
            idevice_error_free(remoteServerError)
            cleanup()
            return .remoteServer(detail)
        }
        NSLog("[Locus] remote_server_connect_rsd ok (RemoteXPC handshake complete)")

        if let simError = location_simulation_new(remoteServer, &locationSimulation) {
            let detail = describe(simError)
            NSLog("[Locus] location_simulation_new failed: %@", detail)
            idevice_error_free(simError)
            cleanup()
            return .simulationCreate(detail)
        }
        NSLog("[Locus] location_simulation_new ok (DVT location simulation service open)")
        // location_simulation_new consumes/owns remote server lifecycle alongside handle
        remoteServer = nil

        if let setError = location_simulation_set(locationSimulation, latitude, longitude) {
            let detail = describe(setError)
            NSLog("[Locus] location_simulation_set failed: %@", detail)
            idevice_error_free(setError)
            cleanup()
            return .locationSet(detail)
        }
        NSLog("[Locus] location_simulation_set ok — locationd should now report the simulated fix")
        return nil
    }

    private static func clearLocked() -> LocationEngineError? {
        guard let locationSimulation else {
            NSLog("[Locus] LocationEngine.clear called with no active session")
            return .locationClear(nil)
        }
        let err = location_simulation_clear(locationSimulation)
        cleanup()
        if let err {
            let detail = describe(err)
            NSLog("[Locus] location_simulation_clear failed: %@", detail)
            idevice_error_free(err)
            return .locationClear(detail)
        }
        NSLog("[Locus] location_simulation_clear ok")
        return nil
    }
}
