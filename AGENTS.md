# Codex Project Rules

## Project Identity

- Project name: `<填入專案名稱>`
- Workflow version: `0.1.0`
- This file defines durable project rules. Conversation memory is not a source of truth.

## Project Goal

在此描述專案目標、使用者價值與明確邊界。

## Source of Truth

正式狀態來源依序為：

1. repository 中已提交的檔案與 Git 歷史；
2. `HANDOFF.md` 的最新交接摘要；
3. `PROJECT_STATE.json` 的機器可讀狀態；
4. `CHANGELOG_AGENT.md` 的追加式歷史。

Codex 不得只依賴對話記憶。

## Repository Structure

- `scripts/workflow/`: 通用工作流腳本。
- `docs/workflow/`: 工作流文件。
- `scripts/project/validate.ps1`: 可選的專案驗證入口。
- 其餘結構由專案自行定義。

## Allowed Changes

只修改使用者要求範圍內的內容。保留既有使用者變更，避免順手重構或擴張範圍。

## Protected Files and Areas

在此列出需先取得明確授權才能修改的檔案、資料夾、生成物或外部系統。

## Required Reading Before Work

Codex 每次開始正式工作前必須依序讀取：

1. `AGENTS.md`
2. `HANDOFF.md`
3. `PROJECT_STATE.json`

之後執行 `scripts/workflow/startup.ps1`，在確認 Git 工作樹、branch、ahead、behind、divergence 與上次交接前不得修改正式專案內容。

## Short Command Protocol

使用者可使用以下單字口令。Codex 必須把它們視為完整工作流請求，不要求使用者重複貼上長指令：

- `開`：執行開工流程。先讀取 `AGENTS.md`、`HANDOFF.md`、`PROJECT_STATE.json`，再執行 `scripts/workflow/startup.ps1 -ApplySafePull`。只有安全條件全部成立時才可 fast-forward pull；確認狀態前不得修改正式內容。
- `收`：執行正式收工流程。驗證、更新交接狀態、檢查敏感與大型檔案，然後依設定安全 commit、push 與建立 handoff package。
- `換`：準備換電腦。執行完整正式收工、push、建立 handoff package，並在已設定時複製外部備份；最後回報 branch、commit SHA、push、validation、ZIP、SHA256、備份狀態與新電腦接續方式。
- `整`：強制蒐集安全的真實來源、產生白話摘要並執行規則式風險檢查；低風險內容自動發布到 Obsidian、單向同步 Google Drive，並更新工作流專屬的 NotebookLM 管理來源；高風險異常只隔離、不上傳。

短口令只縮短使用者輸入，不會放寬任何驗證、Git、敏感資料或失敗回報規則。

## Required Updates Before Shutdown

正式收工必須根據真實結果更新：

- `HANDOFF.md`（只保存最新交接）；
- `PROJECT_STATE.json`（機器可讀狀態）；
- `CHANGELOG_AGENT.md`（追加式歷史）。

## Validation Rules

- 不得偽造 `PASS`、`SUCCESS`、`COMPLETE` 或 `READY`。
- 未設定驗證時必須回報 `NOT_CONFIGURED`，不得視為 PASS。
- 驗證失敗時不得把專案標示為 `COMPLETE` 或 `HANDOFF_READY`。
- 不得為了讓測試通過而刪除、弱化、略過或竄改測試。
- 所有完成宣告必須有實際執行的驗證證據。

### State definitions

- `UNINITIALIZED`: 尚未完成工作流初始化。
- `READY`: 工作流結構已通過初始化驗證，可開始工作。
- `IN_PROGRESS`: 正在進行，仍有後續任務。
- `BLOCKED`: 因明確阻礙無法繼續。
- `VALIDATION_FAILED`: 正式驗證失敗。
- `HANDOFF_READY`: 驗證通過且交接資料已備妥。
- `COMPLETE`: 專案定義的全部完成條件均已達成。

驗證狀態：`PASS`、`FAIL`、`NOT_CONFIGURED`、`BLOCKED`、`SKIPPED`。
Push 狀態：`UNKNOWN`、`NOT_REQUIRED`、`NOT_PUSHED`、`PUSHED`、`FAILED`。
Package 狀態：`NOT_CREATED`、`CREATED`、`COPIED_TO_BACKUP`、`FAILED`。

## Git Safety Rules

- 不得自動 force push、reset --hard、clean -fd。
- 不得覆蓋本機未提交變更或刪除未知檔案。
- branch diverged 時只回報，不得自行 merge 或 rebase。
- 只有工作樹乾淨、local ahead 為 0、local behind 大於 0、有 upstream 且未 diverged，並由使用者明確要求時，才可 `git pull --ff-only`。
- 不得修改全域 Git 設定。

## Sensitive Data Rules

不得提交或打包 API key、token、帳號、email、`.env`、private key、credentials、secrets、本機同步路徑或其他敏感資訊。

## Large File Rules

- 不得自動加入來源不明的大型檔案或不明二進位檔案。
- 超過 `maximumAutoAddFileSizeMB` 的檔案必須停下並回報。
- GitHub 保存正式版本；巨大素材、建置輸出與大型交接包使用明確設定的外部備份。

## Completion Definition

只有需求、驗證、狀態檔、Git 與交接結果皆與事實一致時才可宣稱完成。外部整合未實測時必須明確標示。

## Failure Reporting

任何驗證、commit、push、ZIP 或備份失敗都必須保留真實 exit code 與失敗狀態，不得用成功訊息掩蓋。

## Cross-Device Rules

- 不得假設 Google Drive 路徑或磁碟代號。
- 不得把單台電腦的絕對路徑寫成專案標準。
- 活躍 Git 工作副本放在一般本機磁碟；Google Drive 只接收完成後的備份。
- 換裝置前先驗證、收工、push 並產生交接包；新裝置先讀交接檔再工作。

## Handoff Rules

- `HANDOFF.md` 只保留最新狀態，不累積無限日誌。
- `CHANGELOG_AGENT.md` 追加歷史，不重複完整 handoff。
- 每次交接要記錄時間、agent、電腦、branch、commit、push、validation 與 package 狀態。

## Project-Specific Rules

<!-- 在此追加專案專屬規則。保留上方通用安全規則。 -->

## Project Type Isolation

- 執行整或全整前，必須讀取 workflow.config.json 的 knowledgeProfile.projectType。缺少或不支援時回報 BLOCKED，不得猜測類型或產生正式筆記。
- game：可整理故事與世界觀、角色與 NPC、魔物、招式與戰鬥、城鎮與場景、系統與玩法、物品裝備。
- website：只整理網站目標、頁面與內容、使用流程、介面、搜尋與導覽、部署與維護；禁止遊戲分類。
- web-application：只整理產品功能、帳號權限、資料流程、外部整合、操作方式、部署與維護；禁止遊戲分類。
- tool：只整理工具用途、安裝設定、指令流程、安全界線、整合服務、維護與疑難排解；禁止遊戲分類。
- general：使用專案介紹、主要內容、目前進度、優化與建議、待處理事項；禁止遊戲分類。
- 每份正式總覽必須是白話文，固定更新專案總覽.md，不建立日期副本，不顯示雜湊、來源數量、程式檔清單或內部分類索引。
- 分類規則只來自目前專案的 projectType。不得因其他專案、共用模板、NotebookLM 或 Agent 記憶而混入不相關領域。
