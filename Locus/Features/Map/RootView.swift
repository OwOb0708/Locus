import SwiftUI
import NetworkExtension

struct RootView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @State private var displayedError: String?
    @State private var showSessionError = false

    var body: some View {
        // Bottom chrome is a sibling overlay aligned to the bottom — no full-screen
        // Spacer layer that can steal / pass map taps through the tray.
        ZStack(alignment: .bottom) {
            MapHomeView()

            // Settings/Places now live in MapHomeView's top chrome row; this
            // tray only matters once there's an active session to control.
            if session.isSpoofing || session.joystickActive {
                BottomControlsView()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        .onAppear {
            presentSessionError(session.lastError)
        }
        .onChange(of: session.lastError) { _, error in
            presentSessionError(error)
        }
        .alert("Locus", isPresented: $showSessionError) {
            Button("好", role: .cancel) {
                session.lastError = nil
            }
        } message: {
            Text(displayedError ?? "")
        }
    }

    private func presentSessionError(_ error: String?) {
        guard let error else { return }
        displayedError = error
        showSessionError = true
    }
}

struct StatusBarView: View {
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.scenePhase) private var scenePhase

    @State private var tunnelConnected = LocalDevVPN.isConnected

    private enum Display {
        case notSpoofing
        case connectVPN
        case status(String)
    }

    private var display: Display {
        switch session.status {
        case .idle:
            return tunnelConnected ? .notSpoofing : .connectVPN
        case .connecting:
            return .status("連線中…")
        case .active:
            return .status("模擬定位中")
        case .reconnecting:
            return .status("重新連線中…")
        case .dropped(let reason):
            return .status(reason.isEmpty ? "已斷線" : "已斷線 — \(reason)")
        }
    }

    private var color: Color {
        switch display {
        case .notSpoofing:
            return Color.primary.opacity(0.55)
        case .connectVPN:
            return LocusTheme.statusWarn
        case .status:
            switch session.status {
            case .active: return LocusTheme.statusGood
            case .connecting, .reconnecting: return LocusTheme.statusWarn
            case .dropped: return LocusTheme.statusBad
            case .idle: return Color.primary.opacity(0.55)
            }
        }
    }

    private var title: String {
        switch display {
        case .notSpoofing: return "未模擬定位"
        case .connectVPN: return "請連接 LocalDevVPN"
        case .status(let text): return text
        }
    }

    var body: some View {
        Group {
            if case .connectVPN = display {
                Button(action: LocalDevVPN.openOrInstall) {
                    statusContent
                }
                .buttonStyle(.plain)
            } else {
                statusContent
            }
        }
        .onAppear { refreshTunnel() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshTunnel() }
        }
        .onChange(of: session.status) { _, _ in
            refreshTunnel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NEVPNStatusDidChange)) { _ in
            // LocalDevVPN connection changes show up here even though we don’t own the VPN.
            refreshTunnel()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                refreshTunnel()
            }
        }
    }

    private var statusContent: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.7), radius: 4)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            if case .connectVPN = display {
                Image(systemName: "lock.shield.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LocusTheme.accent)
            } else if case .active = session.status, let sim = session.simulated {
                Text(String(format: "%.4f, %.4f", sim.latitude, sim.longitude))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .locusGlass(.clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func refreshTunnel() {
        tunnelConnected = LocalDevVPN.isConnected
    }
}

/// Bottom tray is deliberately minimal now: how to move is chosen from the
/// map-tap picker (teleport / navigate / multi-stop / joystick), so this bar
/// only needs quick access to settings, favorites, and stopping an active spoof.
struct BottomControlsView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore

    @State private var showSpeedAdjust = false
    @State private var liveMode: TravelMode = .walk
    @State private var liveSpeed: CLLocationSpeed = TravelMode.walk.baseSpeed
    @State private var liveIsCustom = false

    private let trayShape = RoundedRectangle(cornerRadius: 28, style: .continuous)

    var body: some View {
        VStack(spacing: 12) {
            if session.joystickActive {
                JoystickPad { vector in
                    session.updateJoystick(vector: vector)
                }
                .frame(width: 148, height: 148)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            // Two balanced blocks (progress on the left, controls on the
            // right) instead of stacking a right-aligned controls row above
            // a separately-aligned progress row — that left a large diagonal
            // gap between them.
            HStack(alignment: .top, spacing: 14) {
                if let progress = session.routeProgress {
                    RouteProgressView(progress: progress)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 10) {
                    // Lets you change pace while a route/joystick is already
                    // moving — `followRoute`/joystick both read `effectiveSpeed`
                    // live each step, so this takes effect immediately.
                    if session.isSpoofing {
                        Button {
                            liveMode = session.travelMode
                            liveSpeed = session.effectiveSpeed
                            liveIsCustom = session.customSpeed != nil
                            showSpeedAdjust = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "speedometer")
                                Text(String(format: "%.0f km/h", session.effectiveSpeed * 3.6))
                                    .lineLimit(1)
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 10)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 8) {
                        if session.isSpoofing {
                            // Stop just holds at the current spot — this is
                            // the explicit opt-in to actually drop back to
                            // the device's real GPS fix.
                            IconButton(systemName: "location.slash.fill") {
                                session.returnToRealLocation(pairing: pairing)
                            }
                            .accessibilityLabel("回到真實位置")
                        }

                        if session.joystickActive {
                            Button {
                                session.stopJoystick()
                            } label: {
                                Text("結束遙控")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.primary)
                                    .frame(minWidth: 88)
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 10)
                                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }

                        if session.isSpoofing {
                            Button {
                                session.stop(pairing: pairing)
                            } label: {
                                Text("停止")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(minWidth: 64)
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 8)
                                    .background(Capsule().fill(LocusTheme.danger))
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(14)
        .locusGlass(.regular, in: trayShape)
        // Whole tray absorbs taps so near-misses don't fall through to the map.
        .contentShape(trayShape)
        .sheet(isPresented: $showSpeedAdjust) {
            SpeedPickerSheet(
                title: "調整目前速度",
                mode: $liveMode,
                speedMPS: $liveSpeed,
                isCustom: $liveIsCustom,
                tripCount: .constant(1),
                onConfirm: {
                    session.travelMode = liveMode
                    session.customSpeed = liveIsCustom ? liveSpeed : nil
                    session.refreshRouteEstimate()
                },
                onCancel: {}
            )
        }
    }
}

private struct RouteProgressView: View {
    let progress: RouteProgress

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 4) {
                Label(distanceText, systemImage: "point.topleft.down.to.point.bottomright.curvepath")

                HStack(spacing: 6) {
                    Label(countdownText(at: context.date), systemImage: "timer")
                    Text("·").foregroundStyle(.secondary)
                    Text(progress.estimatedArrival, format: .dateTime.hour().minute())
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption.monospacedDigit().weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityElement(children: .combine)
        }
    }

    private var distanceText: String {
        if progress.remainingDistance < 1_000 {
            return "剩餘 \(Int(progress.remainingDistance.rounded())) 公尺"
        }
        return String(format: "剩餘 %.1f 公里", progress.remainingDistance / 1_000)
    }

    private func countdownText(at date: Date) -> String {
        let seconds = max(0, Int(progress.estimatedArrival.timeIntervalSince(date).rounded(.up)))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

struct IconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .locusGlass(.interactive, in: Circle())
        .foregroundStyle(.primary)
    }
}
