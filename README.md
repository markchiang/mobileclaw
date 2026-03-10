<div align="center">
  <img src="assets/logo.jpg" alt="MobileClaw" width="220" />

# MobileClaw

### AI Agent in Your Pocket · OpenClaw-Compatible Workspace · Offline-First Local Data

  <p>
    <img src="https://img.shields.io/badge/Flutter-3.x-02569B?style=flat&logo=flutter&logoColor=white" alt="Flutter" />
    <img src="https://img.shields.io/badge/Dart-3.3+-0175C2?style=flat&logo=dart&logoColor=white" alt="Dart" />
    <img src="https://img.shields.io/badge/Android-Foreground_Service-3DDC84?style=flat&logo=android&logoColor=white" alt="Android" />
    <img src="https://img.shields.io/badge/License-MIT-green" alt="License" />
  </p>

  <p>
    <a href="README.zh.md">中文（PicoClaw 主專案）</a> ·
    <a href="mobileclaw_app/README.md">Flutter 子專案 README</a> ·
    <a href="mobileclaw_app/docs/ARCHITECTURE.md">Architecture</a>
  </p>
</div>

---

> **MobileClaw** 是將 PicoClaw/OpenClaw 核心體驗帶到手機端的 Flutter App：
> 支援多會話聊天、JSONL 記憶、OpenAI-compatible LLM、Workspace 文件工具、排程、心跳檔案、匯入匯出與備份，並透過 Android 前景服務盡可能維持背景 AI Runtime。

## ⚡ 給使用者：先裝 APK，馬上可用

### 1) 下載安裝 APK

1. 前往 GitHub Releases：<https://github.com/sipeed/picoclaw/releases>
2. 下載最新的 Android `*.apk` 安裝檔（MobileClaw）。
3. 在手機上安裝 APK（若系統提示，允許「安裝未知來源應用」）。

> 建議：優先使用最新 Release，以獲得較完整的功能與修正。

### 2) 第一次打開後，完成 LLM 設定

進入 App 的 **Settings** 頁面，填入：

- **API Key**：你的模型服務金鑰
- **Base URL**：服務端點（OpenAI-compatible）
- **Model**：例如你要使用的 chat model 名稱

儲存後回到聊天頁，即可開始對話。

### 3) 可選：設定 Web Search

若你希望 Agent 能搜尋網路，可在 Settings 裡額外填：

- Tavily API Key
- Tavily Base URL
- Max Results

### 4) 可選：匯入既有工作區資料

你可以直接在 Settings 透過下列方式匯入：

- OpenClaw 工作區資料夾
- `*.md` 文件
- `*.zip` 備份包

這樣可以快速復用你原本的 `AGENTS.md / skills / memory` 資料。

## ✨ Why MobileClaw

- 📱 **真行動化 AI Agent**：在手機上就能持續運行 Agent 工作流。
- 🧠 **可持久記憶**：使用 JSONL 記錄會話與摘要，支援多 Session 管理。
- 🔧 **工具可調用**：Agent 可讀寫 Workspace、列目錄、搜尋 Web、管理排程。
- 🔄 **OpenClaw 相容**：支援 `AGENTS.md / SOUL.md / USER.md / skills/**/SKILL.md / memory/**`。
- 🛟 **資料可遷移可備份**：匯入資料夾、匯入 Markdown/Zip、匯出與還原一體化。
- ⚙️ **工程化可測試**：已有多項單元測試覆蓋 runtime、bridge、store 與 service。

## 🚀 Core Features

### 1) Chat + Runtime
- 多聊天 session（建立、切換、摘要標題）。
- 使用 OpenAI-compatible provider 發送對話。
- 支援 tool-calling 迴圈，並限制最大工具迭代次數避免失控。

### 2) Local Memory (JSONL)
- 會話歷史、摘要與 metadata 本地存放。
- 每次對話可回填上下文，維持長程記憶效果。

### 3) Workspace Bridge
- 內建 Workspace 工具（列檔、讀寫 Markdown、一般檔案存取）。
- 啟動時可 seed 預設 workspace（含 `AGENTS.md` 等基礎檔案）。
- 可載入 skills 並提供 Agent 使用。

### 4) Scheduler + HEARTBEAT
- `CronService` 支援一次性 / 週期 / cron-like 任務。
- `HeartbeatService` 週期性更新 `HEARTBEAT.md`，記錄最近事件與任務狀態。

### 5) Migration / Import / Backup
- 匯入 OpenClaw 資料夾。
- 匯入 `*.md` 與 `*.zip`。
- 匯出/還原備份 bundle（workspace + memory）。

### 6) Background Guard (Android)
- 整合 `flutter_foreground_task` 建立前景服務通知。
- 盡量降低系統回收背景 runtime 的機率。

## 🧱 Architecture

`mobileclaw_app` 目前採分層結構：

- `lib/core/models`: 資料模型
- `lib/core/providers`: LLM provider 抽象與實作
- `lib/core/services`: 記憶體存儲、bridge、排程、心跳、備份、runtime loop
- `lib/features/chat`: 聊天頁與控制器
- `lib/features/settings`: 設定、匯入匯出、備份操作

更多可參考：`mobileclaw_app/docs/ARCHITECTURE.md`

## 🛠️ 開發者快速開始

### Prerequisites
- Flutter SDK `>=3.3.0 <4.0.0`
- Android Studio / Android SDK

### 1. Clone
```bash
git clone https://github.com/sipeed/picoclaw.git
cd picoclaw/mobileclaw_app
```

### 2. Install dependencies
```bash
flutter pub get
```

### 3. Run
```bash
flutter run
```

### 4. Test
```bash
flutter test
```

## ⚙️ Runtime / Config Notes

- App 啟動後會在 app support 目錄建立 `mobileclaw/workspace` 與 memory/state 結構。
- LLM 需在設定頁填入 API Key、Base URL、Model。
- Web Search 可配置 Tavily API 與結果上限。
- 最大工具迭代次數可在設定頁調整（避免 tool loop 無限循環）。

## 📁 Workspace Compatibility

MobileClaw 以 OpenClaw 風格管理 workspace，重點檔案包含：

- `AGENTS.md`
- `SOUL.md`
- `USER.md`
- `HEARTBEAT.md`
- `skills/<name>/SKILL.md`
- `memory/**`

這讓你可以在桌面端/雲端工作區與手機端之間維持一致的 Agent 行為與知識結構。

## 🗺️ Roadmap (Suggested)

- [ ] iOS 背景策略最佳化（與系統限制協作）
- [ ] 更完整的多 provider 設定與切換 UX
- [ ] 更強的工具沙箱與權限策略
- [ ] 聊天搜尋、標籤與長對話歸檔
- [ ] E2E 測試與效能追蹤面板

## 🤝 Contributing

歡迎 PR / Issue！

1. Fork repo
2. 建立 feature branch
3. 撰寫/更新測試
4. 送 PR 並描述變更動機、行為差異與測試結果

可先閱讀：`CONTRIBUTING.md`

## 📄 License

MIT License.
