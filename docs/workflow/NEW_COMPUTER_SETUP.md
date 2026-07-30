# 新電腦設定

1. 安裝 Git for Windows 與 Windows PowerShell 5.1 或 PowerShell 7。
2. 使用安全的 GitHub 認證方式存取 private repository；不要把 token 放進專案。
3. 選擇一般本機磁碟作為工作目錄，不要把活躍 `.git` repository 放在即時同步資料夾。
4. clone：

```powershell
git clone <private-repository-url>
cd <project-folder>
```

5. 如需大型備份，安裝 Google Drive Desktop，確認這台電腦的實際同步路徑，建立本機 `workflow.config.json`。不要複製另一台電腦的絕對路徑。
6. 讀 `AGENTS.md`、`HANDOFF.md`、`PROJECT_STATE.json`。
7. 執行：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\workflow\startup.ps1 -ApplySafePull
```

8. 檢查上次 Push Status 必須為 `PUSHED`。若不是，先回到舊電腦或從已驗證的 handoff ZIP 人工復原，禁止猜測或覆蓋。

新電腦第一次可另外執行 `git status --short --branch`、`git remote -v` 與專案驗證，確認工具鏈與環境差異。
