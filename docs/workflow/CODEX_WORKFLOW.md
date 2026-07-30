# Codex 標準工作流

## 最短口令

安裝後，使用者只需要記住：

```text
開始工作：開
結束工作：收
換電腦：換
```

- `開` 等同完整開工流程，包含讀取三個狀態檔與安全 startup。
- `收` 等同正式收工流程，包含驗證、交接、commit、push 與 package。
- `換` 等同換電腦流程，另外要求完整 ZIP、SHA256、備份與新電腦接續報告。

短口令不會放寬安全規則；驗證、push、ZIP 或備份失敗仍必須保留真實狀態。

## 每次開工

1. 讀 `AGENTS.md`、`HANDOFF.md`、`PROJECT_STATE.json`。
2. 執行 `scripts/workflow/startup.ps1`。
3. 檢查 project、computer、branch、working tree、ahead、behind、diverged、validation、push 與 warnings。
4. 只有完整安全條件成立且使用者明確要求時，使用 `-ApplySafePull` 執行 `git pull --ff-only`。
5. 確認交接與 Git 一致後才修改正式內容。

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\workflow\startup.ps1 -ApplySafePull
```

## 工作中

- 只修改任務範圍內內容。
- 不刪除未知檔案、不覆蓋使用者變更。
- 保持 `HANDOFF.md` 為最新摘要，歷史只追加到 `CHANGELOG_AGENT.md`。
- 大型檔案與敏感資料先停下回報。

## 正式收工

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\workflow\shutdown.ps1 `
  -CommitMessage "feat: 描述主要變更"
```

流程會驗證、盤點、檢查敏感與大型檔、更新三個狀態檔、安全 stage/commit、push 與建立交接 ZIP。每個外部結果獨立驗證。`-AllowValidationFailure` 只允許 WIP 診斷交接，不會把 FAIL 改成 PASS。

## 換電腦

舊電腦完成 shutdown，記下 branch、commit、push、validation、ZIP、SHA256 與備份狀態。新電腦 clone private repository，讀三個狀態檔，執行 startup。若 push 非 PUSHED，不得假設遠端已含舊電腦最新內容。

## 第一次建立

1. 執行 repository 的 `installer/install-to-project.ps1`。
2. 編輯 `AGENTS.md`，建立被忽略的 `workflow.config.json`。
3. 設定驗證。
4. 明確 git init、建立 private GitHub repository、首次 commit/push。
5. 第二台電腦 clone 後先 startup。

## 狀態語意

- Project：`UNINITIALIZED`、`READY`、`IN_PROGRESS`、`BLOCKED`、`VALIDATION_FAILED`、`HANDOFF_READY`、`COMPLETE`。
- Validation：`PASS`、`FAIL`、`NOT_CONFIGURED`、`BLOCKED`、`SKIPPED`。
- Push：`UNKNOWN`、`NOT_REQUIRED`、`NOT_PUSHED`、`PUSHED`、`FAILED`。
- Package：`NOT_CREATED`、`CREATED`、`COPIED_TO_BACKUP`、`FAILED`。

只有真實條件符合時才可使用成功狀態。
