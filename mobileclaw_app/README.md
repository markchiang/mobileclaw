<div align="center">
  <h1>📱 MobileClaw</h1>
  <p><strong>把 PicoClaw 核心能力帶到手機上的輕量 AI Agent App（Flutter）</strong></p>

  <p>
    <img src="https://img.shields.io/badge/Flutter-3.x-02569B?style=flat&logo=flutter&logoColor=white" alt="Flutter">
    <img src="https://img.shields.io/badge/Dart-3.3%2B-0175C2?style=flat&logo=dart&logoColor=white" alt="Dart">
    <img src="https://img.shields.io/badge/Platform-Android%20%7C%20iOS-34A853?style=flat" alt="Platform">
    <img src="https://img.shields.io/badge/License-MIT-green?style=flat" alt="License">
  </p>
</div>

---

MobileClaw 是一個以 Flutter 開發的行動端 AI Agent，將 PicoClaw 的核心流程移植為手機可用版本：

- Chat 對話（Markdown 顯示）
- Workspace 記憶與技能檔案管理
- OpenClaw 相容的匯入/匯出與備份還原
- Android 背景常駐（前景服務）

> 專案目前定位為「可用且持續迭代中」的行動端基礎版本，強調本地資料目錄與可攜式 workspace 相容性。

## ✨ 目前已實作功能

- **雙頁面主架構**：`Chat` + `Settings` 底部導覽切換。  
- **多會話聊天**：可建立新對話、切換歷史會話。  
- **Markdown 訊息渲染**：助手回覆以 `flutter_markdown` 顯示。  
- **Workspace 自動初始化**：首次啟動會自動寫入預設 `AGENTS.md / SOUL.md / USER.md / skills/**`。  
- **記憶與排程 Runtime**：包含 heartbeat、cron、JSONL memory store 的背景循環。  
- **OpenClaw Bridge**：支援從外部資料夾、`.md`、`.zip` 匯入，並支援備份包還原。  
- **設定中心**：可設定 LLM profile、Web 搜尋參數、匯入匯出與備份。  
- **品牌字詞遷移流程**：可將舊 `PicoClaw` 身份文件自動轉換為 `MobileClaw`（可先備份）。

## 🧱 架構概覽

```text
lib/
  core/
    models/      # Chat/Skill 等資料模型
    providers/   # LLM provider 抽象與實作
    services/    # runtime、memory、backup、bridge、config、skills
  features/
    chat/        # Chat UI + controller
    settings/    # 設定頁（LLM/Web/備份/匯入匯出）
```

設計目標：維持「`message -> context -> memory -> provider -> persist`」的核心流程，並優先確保與 OpenClaw workspace 互通。

## 🚀 Quick Start

### 1) 環境需求

- Flutter SDK `3.x`
- Dart SDK `>=3.3.0 <4.0.0`
- Android Studio / Xcode（依平台）

### 2) 安裝與啟動

```bash
cd mobileclaw_app
flutter pub get
flutter run
```

### 3) 測試

```bash
cd mobileclaw_app
flutter test
```

## 📂 App 資料與相容性

App 會在 `ApplicationSupportDirectory/mobileclaw` 下管理資料（依平台實際路徑不同），主要包含：

- `workspace/`：`AGENTS.md`, `USER.md`, `SOUL.md`, `skills/**`
- `memory/`：記憶資料
- `config/`：設定檔與遷移決策
- `backups/`：備份 zip

### OpenClaw 相容重點

- 支援匯入 OpenClaw 資料夾
- 支援 `.md` 與 `.zip` 批次匯入
- 支援備份包還原
- 保留 `skills/<name>/SKILL.md` 結構

## 🔋 背景執行策略

Android 端透過 `flutter_foreground_task` 啟用前景服務（常駐通知），讓 AI runtime 在背景時更不容易被系統回收。

## 🗺️ Roadmap（建議）

- [ ] iOS 背景能力策略補強（依平台限制分級）
- [ ] 更完整的 provider 設定 UI（多模型切換/驗證）
- [ ] Chat 體驗優化（串流回覆、長對話效能）
- [ ] 匯入衝突處理（Diff/merge）
- [ ] 端到端測試與釋出流程自動化

## 🤝 Contributing

歡迎 issue / PR：

1. Fork 專案
2. 建立 feature branch
3. 補測試並確保 `flutter test` 通過
4. 發 PR 說明動機、改動點、驗證方式

## 📄 License

MIT
