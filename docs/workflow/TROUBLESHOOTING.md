# 疑難排解

## startup 顯示 DIRTY

檢查 `git status --short --branch`。保留、commit 或由使用者明確處理本機變更；工作流不會 pull，也不得 reset/clean 來消除警告。

## local ahead

先驗證本機 commit 是否正確。ahead > 0 時不 pull；視任務與權限決定安全 push。

## local behind

只有 clean、ahead 0、有 upstream、未 diverged 且使用 `-ApplySafePull` 才 ff-only pull。

## diverged

立即停止自動同步。備份 working tree，閱讀兩邊歷史，由使用者決定 merge 或 rebase。工作流不代替此決策。

## 沒有 upstream

檢查 `git remote -v` 與 branch。首次可人工執行 `git push -u origin <branch>`；不要讓腳本猜 remote。

## Validation NOT_CONFIGURED

在本機 `workflow.config.json` 設定 `validationCommand`，或建立 `scripts/project/validate.ps1`。NOT_CONFIGURED 的 exit code 是 3，不是 PASS。

## Validation FAIL/BLOCKED

查看輸出的 `logPath`。修正真正問題後重跑。`-AllowValidationFailure` 只能建立 WIP 診斷交接，不能改寫狀態。

## Package FAILED

確認輸出路徑可寫、磁碟空間足夠、檔案未被鎖定。package output 會被排除，避免把自己遞迴包入。

## Google Drive FAILED

本地 ZIP 若已建立仍是真實 `CREATED`。確認本機路徑、離線狀態與可用空間後人工重試；不要把本機成功等同雲端同步完成。

## JSON 或 PowerShell 語法錯誤

執行 repository 測試入口。JSON 使用 `ConvertFrom-Json`，PowerShell 使用 parser API 檢查；錯誤時不得宣稱完成。
