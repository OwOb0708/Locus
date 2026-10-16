import Foundation

enum TunnelConfig {
    /// LocalDevVPN's "Device IP" — the peer address its packet-tunnel-provider
    /// intercepts and forwards to the real on-device RemotePairing (remoted)
    /// service. This is what gets dialed by `tunnel_create_rppairing`. It is a
    /// virtual peer address: it never shows up as a local interface address, so
    /// it must NOT be used for connectivity checks (see `localIP` below).
    static let defaultIP = "10.7.0.1"
    static let defaultsKey = "locus.targetDeviceIP"

    /// LocalDevVPN's "Tunnel IP" — the address LocalDevVPN assigns to *this*
    /// iPhone's own utun interface once the VPN is active. Unlike `targetIP`,
    /// this one is a real local interface address, so it's what `LocalDevVPN.isConnected`
    /// should look for in `getifaddrs()`. Dialing it directly would just hit the
    /// local tunnel endpoint itself, not the forwarded device service — that
    /// mismatch is what previously surfaced as a misleading "tunnelCreate" error.
    static let defaultLocalIP = "10.7.1.1"
    static let localDefaultsKey = "locus.localTunnelIP"

    static var targetIP: String {
        let stored = UserDefaults.standard.string(forKey: defaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let stored, !stored.isEmpty else { return defaultIP }
        return stored
    }

    static func setTargetIP(_ value: String) {
        UserDefaults.standard.set(value, forKey: defaultsKey)
    }

    static var localIP: String {
        let stored = UserDefaults.standard.string(forKey: localDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let stored, !stored.isEmpty else { return defaultLocalIP }
        return stored
    }

    static func setLocalIP(_ value: String) {
        UserDefaults.standard.set(value, forKey: localDefaultsKey)
    }
}
