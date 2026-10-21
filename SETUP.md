# Locus — 安裝與第一次瞬移

## 1. 側載 IPA

從 [Releases](https://github.com/OwOb0708/Locus/releases) 安裝最新的 IPA（或自行從原始碼編譯），用 Feather、SideStore、AltStore、Sideloadly 或 LiveContainer 都可以。

Bundle ID：`com.chrismack.locus`

### LiveContainer

在 LiveContainer 裡，檔案選擇器常常會壞掉。可以用下面任一種方式解決：

1. 在 LiveContainer 裡長按 **Locus** → **設定** → 開啟 **修正檔案選擇器**，再試一次匯入。
2. 用 iOS 分享選單把配對檔案分享／開啟**到 LiveContainer → Locus**。
3. 複製 RPPairing 的 plist 內容，打開 Locus → **從剪貼簿貼上 RPPairing**（設定精靈或「設定」頁都有）。

## 2. 配對

### iOS 27——不需要電腦

1. 打開 Locus → **設定 → 在這支 iPhone 上配對** → **開始配對**。
2. 允許**區域網路**（如果有跳出定位／通知權限也一併允許）。
3. 讓 Locus 保持在前景。到**設定 ›「隱私權與安全性」›「開發者模式」› 與主機配對**。
4. 選 **Locus** → **配對**。
5. 先輸入你的 **iPhone 解鎖密碼**（這一步是授權配對）。
6. 第二個提示出現時，輸入 Locus 顯示的 **6 位數代碼**（也會用通知推播出來）。
7. 完成——RPPairing 檔案已經存在裝置上了。

### iOS 18–26

1. 在電腦上下載 [idevice_pair](https://github.com/jkcoxson/idevice_pair/releases)。
2. 接上 iPhone，解鎖，按「信任」。
3. 產生一份 **RPPairing** 檔案（不是 lockdown／SideStore 的 `.mobiledevicepairing`）。
4. AirDrop／分享 → 在 **Locus** 裡開啟、匯入，或用「從剪貼簿貼上」。

## 3. LocalDevVPN

安裝 [LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044)，連線（預設穿隧 IP 是 `10.7.0.1`）。

## 4. 第一次移動

在 Wi‑Fi 下：點地圖放一個圖釘，地圖會自動置中，底部會跳出選單：

- **傳送**：瞬間跳到那個點。
- **導航**：從你目前的位置（或目前模擬的位置）自動規劃路線走過去，走之前可以選走路／跑步／騎車／開車，也能自訂精確速度。
- **多點模式**：選了之後繼續點地圖加入更多點，按「完成」會依序走訪——起點是你目前的位置，第一個點是第一個圖釘。
- **搖桿**：直接在那個點打開搖桿，自己手動操控移動。

移動中（不管是走路線還是搖桿）都可以隨時按底部工具列的速度按鈕即時調整速度，不用停下來重設。開始之後，連線可以繼續在行動網路下運作。
