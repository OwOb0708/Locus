import SwiftUI
import UniformTypeIdentifiers

/// First-run walkthrough: welcome → pairing → LocalDevVPN → map.
/// Skipped when `SetupGate.isComplete` (see `LocusApp`).
struct SetupFlowView: View {
    @EnvironmentObject private var pairing: PairingStore
    @EnvironmentObject private var session: SpoofSession

    var onFinished: () -> Void

    @State private var step: Step
    @State private var appear = false
    @State private var showImporter = false
    @State private var localDevVPNInstalled = LocalDevVPN.isInstalled
    @State private var displayedError: String?
    @State private var showSessionError = false
    @Environment(\.scenePhase) private var scenePhase

    enum Step: Int, CaseIterable {
        case welcome
        case pairing
        case vpn
    }

    init(initialStep: Step = .welcome, onFinished: @escaping () -> Void) {
        _step = State(initialValue: initialStep)
        self.onFinished = onFinished
    }

    private var supportsOnDevicePairing: Bool {
        if #available(iOS 27.0, *) { return true }
        return false
    }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                progressBar
                    .padding(.horizontal, 24)
                    .padding(.top, 12)

                Group {
                    switch step {
                    case .welcome:
                        welcomePage
                    case .pairing:
                        pairingPage
                    case .vpn:
                        vpnPage
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(step)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
            .padding(.bottom, 8)
        }
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: step)
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) { appear = true }
            localDevVPNInstalled = LocalDevVPN.isInstalled
            presentSessionError(session.lastError)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                localDevVPNInstalled = LocalDevVPN.isInstalled
            }
        }
        .onChange(of: step) { _, newStep in
            if newStep == .vpn {
                localDevVPNInstalled = LocalDevVPN.isInstalled
            }
        }
        .onChange(of: pairing.hasPairingFile) { _, hasFile in
            if hasFile, step == .welcome || step == .pairing {
                SetupGate.markInProgress()
                withAnimation { step = .vpn }
            }
        }
        .onChange(of: session.lastError) { _, error in
            presentSessionError(error)
        }
        .sheet(isPresented: $showImporter) {
            PairingDocumentPicker(
                onPick: { url in
                    showImporter = false
                    do {
                        try pairing.importPairing(from: url)
                        withAnimation { step = .vpn }
                    } catch {
                        session.lastError = error.localizedDescription
                    }
                },
                onCancel: { showImporter = false }
            )
            .ignoresSafeArea()
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

    // MARK: - Chrome

    private var background: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Soft map-adjacent atmosphere (no flat fill).
            RadialGradient(
                colors: [
                    LocusTheme.accent.opacity(0.22),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 420
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color(red: 0.12, green: 0.18, blue: 0.28).opacity(0.9),
                    Color.clear
                ],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 380
            )
            .ignoresSafeArea()

            // Subtle grid suggestion of a map without competing with copy.
            GeometryReader { geo in
                Path { path in
                    let spacing: CGFloat = 44
                    for x in stride(from: 0, through: geo.size.width, by: spacing) {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: geo.size.height))
                    }
                    for y in stride(from: 0, through: geo.size.height, by: spacing) {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                }
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
            }
            .ignoresSafeArea()
        }
    }

    private var progressBar: some View {
        HStack(spacing: 8) {
            ForEach(Step.allCases, id: \.rawValue) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? LocusTheme.accent : Color.white.opacity(0.12))
                    .frame(height: 3)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 \(step.rawValue + 1) 步，共 \(Step.allCases.count) 步")
    }

    // MARK: - Welcome

    private var welcomePage: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            VStack(spacing: 20) {
                Image(systemName: "location.north.circle.fill")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(LocusTheme.accent)
                    .symbolEffect(.pulse, options: .repeating.speed(0.4), isActive: appear)
                    .opacity(appear ? 1 : 0)
                    .scaleEffect(appear ? 1 : 0.85)

                VStack(spacing: 10) {
                    Text("Locus")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .tracking(-0.5)

                    Text("瞬移你的定位。\n不需要電腦。")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 12)
            }
            .padding(.horizontal, 28)

            Spacer()

            VStack(spacing: 14) {
                Text("簡單設定一下——大概兩分鐘。")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)

                primaryButton("開始設定") {
                    SetupGate.markInProgress()
                    withAnimation { step = .pairing }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
            .opacity(appear ? 1 : 0)
        }
    }

    // MARK: - Pairing

    private var pairingPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("連接這支 iPhone")
                    .font(.title.weight(.bold))
                Text(supportsOnDevicePairing
                     ? "Locus 需要先完成一次性配對才能設定你的定位。你會在「設定」裡確認一組簡短的代碼。"
                     : "從你的電腦匯入一份配對檔案——Locus 會用它在這支裝置上安全地設定定位。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 16)

            if supportsOnDevicePairing {
                PairOnDeviceView(mode: .embedded) {
                    withAnimation { step = .vpn }
                }
                .environmentObject(pairing)
            } else {
                importPairingCard
                    .padding(.horizontal, 24)
                Spacer()
                VStack(spacing: 12) {
                    primaryButton("匯入配對檔案") {
                        showImporter = true
                    }
                    Button {
                        do {
                            try pairing.importPairingFromClipboard()
                            withAnimation { step = .vpn }
                        } catch {
                            session.lastError = error.localizedDescription
                        }
                    } label: {
                        Text("從剪貼簿貼上")
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .locusGlass(.interactive, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
    }

    private var importPairingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepRow(1, "在 Mac 上執行 idevice_pair，產生一份 RPPairing 檔案。")
            stepRow(2, "用 AirDrop／分享傳進 Locus，或直接複製 plist 文字內容。")
            stepRow(3, "點「匯入」，如果檔案選擇器打不開（LiveContainer），改用「從剪貼簿貼上」。")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func stepRow(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.black)
                .frame(width: 22, height: 22)
                .background(LocusTheme.accent, in: Circle())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - LocalDevVPN

    private var vpnPage: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            VStack(spacing: 22) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(LocusTheme.accent)

                VStack(spacing: 10) {
                    Text(localDevVPNInstalled ? "連接 LocalDevVPN" : "還差一個 App")
                        .font(.title.weight(.bold))

                    Text(localDevVPNInstalled
                         ? "LocalDevVPN 已安裝。打開它啟用 Locus 需要的私有穿隧通道，再回到這裡。"
                         : "LocalDevVPN 會建立一條私有穿隧通道，讓 Locus 可以跟你手機的定位系統溝通。安裝、開啟它之後，就可以開始瞬移了。")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 12) {
                    if localDevVPNInstalled {
                        tipRow(systemImage: "checkmark.circle.fill", title: "已安裝", detail: "LocalDevVPN 已經在這支 iPhone 上了。")
                        tipRow(systemImage: "power.circle.fill", title: "連接", detail: "點下面的按鈕打開它並啟動穿隧通道，之後會自動跳回 Locus。")
                    } else {
                        tipRow(systemImage: "arrow.down.app.fill", title: "安裝", detail: "到 App Store 取得 LocalDevVPN。")
                        tipRow(systemImage: "power.circle.fill", title: "連接", detail: "打開它並啟用 VPN，預設的 IP 設定不用更動。")
                    }
                    tipRow(systemImage: "wifi", title: "第一次瞬移請用 Wi‑Fi", detail: "第一次瞬移請在 Wi‑Fi 環境下進行，之後可以繼續在行動網路下運作。")
                }
                .padding(18)
                .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    if localDevVPNInstalled {
                        LocalDevVPN.openInstalled()
                    } else {
                        LocalDevVPN.openAppStore()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: localDevVPNInstalled ? "lock.shield.fill" : "apple.logo")
                        Text(localDevVPNInstalled ? "開啟 LocalDevVPN" : "取得 LocalDevVPN")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(.primary)
                    .locusGlass(.interactive, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)

                primaryButton("已經連接好了——繼續") {
                    onFinished()
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
    }

    private func tipRow(systemImage: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(LocusTheme.accent)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Shared

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Capsule().fill(LocusTheme.accent))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Gate

enum SetupGate {
    static let defaultsKey = "locus.setupComplete"
    static let inProgressKey = "locus.setupInProgress"

    static var isComplete: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    static var isInProgress: Bool {
        UserDefaults.standard.bool(forKey: inProgressKey)
    }

    static func markInProgress() {
        UserDefaults.standard.set(true, forKey: inProgressKey)
    }

    static func markComplete() {
        UserDefaults.standard.set(true, forKey: defaultsKey)
        UserDefaults.standard.set(false, forKey: inProgressKey)
    }

    /// Already paired *during* this walkthrough → LocalDevVPN page.
    /// Fresh install → welcome. Already-paired upgrades are handled in `LocusApp`.
    static func initialStep(hasPairingFile: Bool) -> SetupFlowView.Step {
        if hasPairingFile, isInProgress { return .vpn }
        return .welcome
    }
}
