import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var pairing: PairingStore
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss

    @State private var showImporter = false
    @State private var showPairOnDevice = false
    @State private var showNameEasterEgg = false
    @State private var tunnelIP = TunnelConfig.targetIP
    @State private var localTunnelIP = TunnelConfig.localIP
    @State private var localDevVPNInstalled = LocalDevVPN.isInstalled
    @Environment(\.scenePhase) private var scenePhase

    private var supportsOnDevicePairing: Bool {
        if #available(iOS 27.0, *) { return true }
        return false
    }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? short : "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        Text(pairing.hasPairingFile ? "已安裝 RPPairing 檔案" : "尚未有配對檔案")
                    } icon: {
                        Image(systemName: pairing.hasPairingFile ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(pairing.hasPairingFile ? LocusTheme.statusGood : LocusTheme.statusWarn)
                    }

                    if supportsOnDevicePairing {
                        Button {
                            showPairOnDevice = true
                        } label: {
                            Label("在這支 iPhone 上配對", systemImage: "iphone.gen3.radiowaves.left.and.right")
                        }
                    }

                    Button("匯入 RPPairing 檔案…") { showImporter = true }
                    Button("從剪貼簿貼上 RPPairing") {
                        do {
                            try pairing.importPairingFromClipboard()
                        } catch {
                            session.lastError = error.localizedDescription
                        }
                    }
                    if pairing.hasPairingFile {
                        Button("移除配對檔案", role: .destructive) {
                            try? pairing.removePairing()
                        }
                    }
                } header: {
                    Text("開發者配對")
                } footer: {
                    Text(supportsOnDevicePairing
                         ? "iOS 27 上可以用「在這支 iPhone 上配對」——不需要電腦。Locus 會廣播一個可配對的主機，請到「設定」›「隱私權與安全性」›「開發者模式」›「與主機配對」確認那組 6 位數代碼。舊版 iOS 則請匯入 idevice_pair 產生的 RPPairing 檔案（不是 SideStore 的 .mobiledevicepairing）。LiveContainer 使用者：在 Locus 開啟「修正檔案選擇器」，或改用貼上／分享到 LiveContainer → Locus。"
                         : "請匯入 idevice_pair 產生的 RPPairing 檔案（不是 SideStore 的 .mobiledevicepairing）。如果檔案選擇器打不開（LiveContainer 常見問題），可以在該 App 開啟「修正檔案選擇器」、把檔案分享到 LiveContainer → Locus，或直接複製 plist 內容後用貼上。")
                }

                Section {
                    TextField("Device IP（撥號目標）", text: $tunnelIP)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit {
                            TunnelConfig.setTargetIP(tunnelIP)
                        }
                    TextField("Tunnel IP（這支 iPhone 自己）", text: $localTunnelIP)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit {
                            TunnelConfig.setLocalIP(localTunnelIP)
                        }
                    LabeledContent("狀態") {
                        Text(LocalDevVPN.isConnected ? "VPN 已連線" : "VPN 未連線")
                            .foregroundStyle(LocalDevVPN.isConnected ? LocusTheme.statusGood : LocusTheme.statusWarn)
                    }
                    Button("儲存穿隧設定") {
                        TunnelConfig.setTargetIP(tunnelIP)
                        TunnelConfig.setLocalIP(localTunnelIP)
                    }
                    Button {
                        if localDevVPNInstalled {
                            LocalDevVPN.openInstalled()
                        } else {
                            LocalDevVPN.openAppStore()
                        }
                    } label: {
                        Label(
                            localDevVPNInstalled ? "開啟 LocalDevVPN" : "取得 LocalDevVPN（App Store）",
                            systemImage: localDevVPNInstalled ? "lock.shield.fill" : "arrow.down.app.fill"
                        )
                    }
                } header: {
                    Text("穿隧通道")
                } footer: {
                    Text("LocalDevVPN 畫面上會顯示兩個不同的號碼，請照上面標示的名稱原樣填入：「Device IP」（預設 10.7.0.1）是 Locus 要撥號連去你手機開發者服務的位址；「Tunnel IP」（預設 10.7.1.1）是 LocalDevVPN 指派給這支 iPhone 自己的位址，只用來確認穿隧通道是否建立。這裡的「狀態」只代表 VPN 網路層是否連通，不代表定位注入本身是否成功——要確認的話請看地圖上方的狀態列，或是 Xcode 主控台的紀錄。第一次瞬移建議先在 Wi‑Fi 下進行，之後可以在行動網路下繼續運作。")
                }

                Section("隱私權") {
                    Text("完全在裝置端處理。收藏與最近紀錄只存在 UserDefaults 裡，沒有任何分析、帳號或上傳行為。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("關於") {
                    LabeledContent("版本", value: appVersion)
                    LabeledContent("引擎", value: "idevice DVT 定位模擬")
                    Text("Locus 是免費且開源的（MIT 授權）。定位注入使用同樣採 MIT 授權的 idevice FFI。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        showNameEasterEgg = true
                    } label: {
                        Text("locus，n. ——「所在之處」。源自拉丁文，意指你所在的位置。")
                            .font(.footnote.italic())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .navigationTitle("設定")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") {
                        TunnelConfig.setTargetIP(tunnelIP)
                        TunnelConfig.setLocalIP(localTunnelIP)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showImporter) {
            PairingDocumentPicker(
                onPick: { url in
                    showImporter = false
                    do {
                        try pairing.importPairing(from: url)
                    } catch {
                        session.lastError = error.localizedDescription
                    }
                },
                onCancel: { showImporter = false }
            )
            .ignoresSafeArea()
        }
            .sheet(isPresented: $showPairOnDevice) {
                PairOnDeviceView()
                    .environmentObject(pairing)
            }
            .fullScreenCover(isPresented: $showNameEasterEgg) {
                LocusEasterEggView()
            }
            .onAppear {
                localDevVPNInstalled = LocalDevVPN.isInstalled
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    localDevVPNInstalled = LocalDevVPN.isInstalled
                }
            }
        }
    }
}

struct PlacesView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Environment(\.dismiss) private var dismiss

    @State private var placeToEdit: SavedPlace?

    /// Groups favorites by their category label (uncategorized ones last),
    /// preserving the order categories first appeared in.
    private var groupedFavorites: [(key: String, color: Color, places: [SavedPlace])] {
        let uncategorized = "未分類"
        var order: [String] = []
        var buckets: [String: [SavedPlace]] = [:]
        var colors: [String: Color] = [:]
        for place in session.favorites {
            let key = place.displayCategory ?? uncategorized
            if buckets[key] == nil {
                buckets[key] = []
                order.append(key)
                colors[key] = place.resolvedColor
            }
            buckets[key, default: []].append(place)
        }
        let orderedKeys = order.filter { $0 != uncategorized } + order.filter { $0 == uncategorized }
        return orderedKeys.map { ($0, colors[$0] ?? Color.primary.opacity(0.4), buckets[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                if session.favorites.isEmpty {
                    Section("收藏") {
                        Text("在地圖上幫圖釘按星號就能收藏。")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(groupedFavorites, id: \.key) { group in
                        Section {
                            ForEach(group.places) { place in
                                placeButton(place)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            session.removeFavorite(place)
                                        } label: {
                                            Label("刪除", systemImage: "trash.fill")
                                        }
                                        Button {
                                            placeToEdit = place
                                        } label: {
                                            Label("編輯", systemImage: "pencil")
                                        }
                                        .tint(.gray)
                                    }
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Circle().fill(group.color).frame(width: 8, height: 8)
                                Text(group.key)
                            }
                        }
                    }
                }

                Section("最近紀錄") {
                    if session.recents.isEmpty {
                        Text("瞬移過的地點會顯示在這裡。")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(session.recents) { place in
                        placeButton(place)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    session.removeRecent(place)
                                } label: {
                                    Label("刪除", systemImage: "trash.fill")
                                }
                            }
                    }
                }
            }
            .navigationTitle("地點")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(item: $placeToEdit) { place in
                EditFavoriteSheet(place: place) { name, categoryName, categoryColor in
                    session.updateFavorite(place, name: name, categoryName: categoryName, categoryColor: categoryColor)
                }
            }
        }
    }

    private func placeButton(_ place: SavedPlace) -> some View {
        Button {
            session.teleport(to: place.coordinate, pairing: pairing)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Circle().fill(place.resolvedColor).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name).foregroundStyle(.primary)
                    Text(String(format: "%.5f, %.5f", place.latitude, place.longitude))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Name + optional category label/color for a favorite. Used both when
/// starring a new place later and when editing one from the Places list.
private struct EditFavoriteSheet: View {
    let place: SavedPlace
    var onSave: (_ name: String, _ categoryName: String?, _ categoryColor: PlaceCategoryColor?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var categoryName: String
    @State private var categoryColor: PlaceCategoryColor?

    init(place: SavedPlace, onSave: @escaping (String, String?, PlaceCategoryColor?) -> Void) {
        self.place = place
        self.onSave = onSave
        _name = State(initialValue: place.name)
        _categoryName = State(initialValue: place.displayCategory ?? "")
        _categoryColor = State(initialValue: place.categoryColor)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("名稱") {
                    TextField("名稱", text: $name)
                }
                Section("分類") {
                    TextField("分類名稱（例如：補給點、A 區）", text: $categoryName)
                    HStack(spacing: 14) {
                        ForEach(PlaceCategoryColor.allCases) { swatch in
                            Button {
                                categoryColor = swatch
                            } label: {
                                Circle()
                                    .fill(swatch.color)
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.primary, lineWidth: categoryColor == swatch ? 2 : 0)
                                            .padding(-3)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                        if categoryColor != nil {
                            Button {
                                categoryColor = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("編輯地點")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        onSave(name, categoryName, categoryColor)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.height(360)])
    }
}
