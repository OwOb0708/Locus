# Locus

免費且開源的 iPhone 定位瞬移工具。點地圖、搜尋地點，或沿路線移動——Locus 透過 Apple 的**開發者定位服務**把座標注入 `locationd`，所以地圖和其他 App 看到的是真正被模擬的 GPS（不是靠 Wi‑Fi 定位猜測，之後會被戶外 GPS 蓋掉的那種）。

<p align="center">
  <img src="docs/screenshots/map.png" alt="Locus 地圖與模擬圖釘" width="180" />
  <img src="docs/screenshots/spoofing.png" alt="Locus 模擬定位畫面" width="180" />
  <img src="docs/screenshots/joystick.png" alt="Locus 搖桿操控" width="180" />
  <img src="docs/screenshots/route.png" alt="Locus 地圖上的路線" width="180" />
</p>

> 上面的截圖是舊版介面，實際畫面已經改版（新的點地圖選單、底部工具列都不一樣），截圖之後會更新。

## 功能

- 點地圖放圖釘，立即選擇這次要怎麼移動：**傳送**（瞬移）、**導航**（從目前位置自動規劃路線）、**多點模式**（依序走訪你放的每個點）、**搖桿**（即時手動操控）
- 依真實道路與人行步道規劃路線（MapKit），支援走路／跑步／騎車／開車
- 除了預設的速度檔位，也能自訂精確速度，而且路線或搖桿移動中可以即時調整，不用先停下來重設
- 匯入／匯出 GPX 路線
- 背景保持連線＋即時狀態列＋斷線通知
- 收藏與最近地點
- 首次使用設定精靈
- 完全在裝置端運作——沒有任何分析或上傳行為

## 安裝

完整步驟請看 [SETUP.md](SETUP.md)。你可以到 [Releases](https://github.com/OwOb0708/Locus/releases) 抓已經編譯好的 IPA，或是照下面的方式自己從原始碼編譯。

Bundle ID：`com.chrismack.locus`

### LiveContainer

在 LiveContainer 裡，檔案選擇器常常會失效。可以用下面任一種方式解決：

1. 長按 **Locus** → **設定** → 開啟 **修正檔案選擇器**，再試一次匯入。
2. 把配對檔案分享**到 LiveContainer → Locus**。
3. 複製 RPPairing 的 plist 內容 → 在 Locus 裡用**從剪貼簿貼上 RPPairing**（設定精靈或「設定」頁都有）。

## 運作原理

Locus 使用 MIT 授權的 [idevice](https://github.com/jkcoxson/idevice) FFI，透過裝置端的開發者穿隧通道跟 Apple 的 DVT 定位模擬服務溝通（跟 Xcode 用的是同一類機制）。

**iOS 27：**到「設定」→ **在這支 iPhone 上配對**，會廣播 `_remotepairing-pairable-host._tcp`。到「設定」›「隱私權與安全性」›「開發者模式」›「與主機配對」確認那組 6 位數代碼即可——不需要電腦。

**iOS 18–26：**用 [idevice_pair](https://github.com/jkcoxson/idevice_pair/releases) 匯入一次 **RPPairing** 檔案。

另外要安裝 **[LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044)**（本機迴圈穿隧通道，預設 `10.7.0.1`），再把 Locus 側載上去。

第一次瞬移建議先在 Wi‑Fi 下進行，之後連線可以在行動網路下繼續運作。

### Pokémon GO 及類似遊戲

Locus 跟 Xcode 開發工具用的是同一種定位模擬方式：告訴 iOS「你在這裡」，其他 App 會從系統讀到這個結果。單純相信 GPS 的 App（Apple 地圖等）都會照著跑。

**Pokémon GO 是例外。** 它有自己一套定位檢查機制，通常會拒絕開發者／模擬的 GPS（例如出現「Failed to detect location」）。這是這種方法本來就會遇到的狀況，不是 Locus 的問題，這個 App 也沒有支援的解法。

像 **iPogo**（以及 SpooferPro 等類似的改版客戶端）運作方式不同：它們是**修改過的 Pokémon GO App 本身**，不是系統層級的定位模擬。功能是做在*那個被改過的遊戲用戶端裡面*，而不是像 Locus 這樣透過 iOS 系統把座標餵給所有 App。Locus 不會修補或取代 Pokémon GO，它只改變系統回報的內容。所以那類工具在 Pokémon GO 裡「看起來有效」，而 Locus 正確地驅動了地圖，卻還是會被 Pokémon GO 自己的檢查擋下來。

Locus 是系統層級的定位瞬移工具，不是 Pokémon GO 用戶端，也不是反偵測外掛。

## 編譯

從原始碼編譯需要一組 Apple Developer 帳號（免費或付費皆可）來做程式碼簽署。官方發布的 IPA **不需要**——直接側載就好。

1. 如果還沒裝，先安裝 [XcodeGen](https://github.com/yonaskolb/XcodeGen)：`brew install xcodegen`
2. 在 `project.yml` 裡設定你的 **Team ID**（`DEVELOPMENT_TEAM`），或是在產生專案後到 Xcode → Signing & Capabilities 選你的 Team。
3. 產生並打開專案：

```bash
xcodegen generate
open Locus.xcodeproj
```

或是用命令列編譯（把下面的 Team ID 換成你自己的，到 [developer.apple.com/account](https://developer.apple.com/account) → Membership 查）：

```bash
xcodegen generate
xcodebuild -project Locus.xcodeproj -scheme Locus -configuration Release \
  -destination 'generic/platform=iOS' DEVELOPMENT_TEAM=YOUR_TEAM_ID build
```

## 授權

MIT 授權。`Vendor/idevice` 內含 idevice FFI（同樣是 MIT 授權）。Locus 是獨立的開源專案，與 Mirage／Wapixel 沒有任何關係。
