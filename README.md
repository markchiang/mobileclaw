# MobileClaw

> PicoClaw → MobileClaw 的移植工程（進行中）

這個專案目前正在把原本以 Go 為核心的 PicoClaw 能力，逐步移植到以 Flutter 為前端/執行容器的 `mobileclaw_app`，目標是讓 Mobile 端可以在維持核心能力的前提下，擁有更好的在地化體驗與設定流程。

## 為什麼要重寫這份 README

目前專案已不只是原始 PicoClaw：

- 根目錄仍保留大量上游介紹（硬體宣傳、歷史新聞、舊品牌敘述）
- 實際開發重心已包含 `mobileclaw_app` 與品牌遷移（`picoclaw` → `mobileclaw`）
- 新進開發者需要的是「現況導向」文件，而不是上游發佈文案

這份 README 會聚焦在 **現在已經做了什麼、如何啟動、下一步做什麼**。

---

## 專案現況（Port 進度）

### 已完成（可用）

- Go 核心專案可建置、測試與執行（CLI/Gateway 仍在）
- Flutter app 基礎框架已建立（聊天、設定、文件檢視等頁面）
- 基礎服務層已具雛形：
  - LLM 設定儲存
  - JSONL 記憶儲存
  - skills 載入
  - runtime/bridge 相關測試
- 品牌文字遷移邏輯已存在（偵測並將 `picoclaw` 用詞替換為 `mobileclaw`）

### 進行中

- 上游功能對齊（Go ↔ Flutter）
- UI/設定流程整合與穩定性
- 文件全面更新（本 README 即其中一環）

### 尚未完成（預期）

- 全量功能 parity（與上游所有 provider/tool/channel 完全對齊）
- 完整發版流程（mobile release checklist）
- 使用者導向的遷移工具與升級指南

---

## 系統架構（目前）

```text
mobileclaw/
├─ cmd/                 # Go 入口（picoclaw、launcher）
├─ pkg/                 # Go 核心模組（agent/providers/tools/channels/...）
├─ mobileclaw_app/      # Flutter App（正在承接與重構行動端體驗）
├─ docs/                # 設計與遷移文件
├─ scripts/             # 開發/測試腳本
└─ Makefile             # Go build/test 工作流
```

設計上採「**核心能力可延續、行動端逐步重構**」策略：

1. 先保留 Go 核心能力與開發效率
2. 在 Flutter 端建立可維護的狀態管理與設定存取
3. 逐步把使用者主流程搬到 mobile 友善介面

---

## 開發環境需求

- Go `1.21+`
- Flutter `3.3+`（Dart `>=3.3.0 <4.0.0`）
- Android Studio / Xcode（依目標平台）

---

## 快速開始

## 1) 取得原始碼

```bash
git clone <your-fork-or-this-repo-url>
cd mobileclaw
```

## 2) 啟動 Go 核心（可選，但建議）

```bash
make deps
make build
./build/picoclaw --help
```

## 3) 啟動 Flutter App

```bash
cd mobileclaw_app
flutter pub get
flutter run
```

---

## 常用開發指令

## Go

```bash
make build          # 建置
make test           # 測試
make vet            # 靜態檢查
make lint           # 程式碼檢查（需 golangci-lint）
```

## Flutter

```bash
cd mobileclaw_app
flutter analyze
flutter test
flutter run
```

---

## 設定與資料

- Go 端預設家目錄：`~/.picoclaw`（上游相容）
- Mobile 端資料：由 app 寫入平台 application support 目錄中的 `mobileclaw` 子目錄
- 品牌遷移：app 內含 `picoclaw` → `mobileclaw` 的偵測與替換流程，避免舊資料直接失效

> 註：目前處於過渡期，命名與資料路徑可能同時出現 `picoclaw` 與 `mobileclaw`，屬預期現象。

---

## 建議 README 章節清單（給後續維護者）

若後續要再擴充文件，建議固定保留以下章節：

1. 專案定位與目標（為何存在）
2. 當前進度（已完成 / 進行中 / 未完成）
3. 架構圖與模組責任
4. 快速開始（最短路徑）
5. 開發指令與測試方式
6. 設定/資料相容與遷移說明
7. Roadmap（下一版本重點）
8. 貢獻流程（commit/PR 規範）
9. 常見問題（FAQ）

---

## Roadmap（建議）

- [ ] 完成 Mobile 主要使用者旅程（首次啟動、設定 provider、第一次對話）
- [ ] 對齊核心能力矩陣（tools、memory、skills、channels）
- [ ] 建立 migration helper（舊設定一鍵導入）
- [ ] 補齊 CI（Go + Flutter）與 release note 模板
- [ ] 更新多語 README（`README.zh.md` 等）與使用者文件

---

## 授權

沿用專案既有授權（請參考 `LICENSE`）。
