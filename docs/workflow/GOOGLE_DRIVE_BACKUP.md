# Google Drive 大型備份

## 設定

1. 安裝並登入 Google Drive Desktop。
2. 由檔案總管確認實際同步資料夾與離線可用狀態。
3. 在被 Git 忽略的 `workflow.config.json` 設定：

```json
{
  "copyPackageToGoogleDrive": true,
  "googleDriveBackupDirectory": "<這台電腦的實際完整路徑>"
}
```

路徑不得提交。不得假設是 `G:\` 或任何固定磁碟代號；每台電腦可不同。

## 為什麼不放活躍 repository

Google Drive 會在背景同步、重新命名與建立衝突副本；Git 同時頻繁更新 `.git` metadata。兩者競爭可能產生不一致或損壞。活躍工作副本應在一般本機磁碟，只有完整 ZIP 在關閉寫入、驗證可讀與算出 SHA256 後才複製。

## 收工與同步完成

1. `create_handoff_package.ps1` 先建立本地 staging 與 ZIP。
2. 開啟 ZIP 驗證可讀，計算 SHA256。
3. 複製到設定路徑。
4. 重新比對大小與 SHA256。
5. 在 Google Drive Desktop 狀態或檔案總管同步圖示確認上傳完成後才關機。

工作流只能驗證本機同步資料夾中的副本，無法證明雲端伺服器已完成上傳；此項必須人工確認，不能標示為自動 PASS。

## 新電腦確認

確認 ZIP 已出現並完成下載；比對舊電腦記錄的大小與：

```powershell
Get-FileHash -LiteralPath "<zip-path>" -Algorithm SHA256
```

先解壓到新的暫存目錄，讀 `manifest.json` 與 `SHA256SUMS`，不要直接覆蓋活躍 repository。

## 例外處理

- **路徑不存在**：本地 ZIP 保留為 `CREATED`，備份為 `FAILED`；修正本機設定後再複製。
- **暫時離線**：不要宣稱雲端備份完成。保留本地 ZIP，連線恢復後再同步與核對。
- **衝突副本**：工作流預設排除 `conflicted copy` 與「衝突的副本」。人工比較來源、時間與 hash；不得自動提交或打包。
- **同步中關機**：重新開機後檢查 Drive 狀態；雲端另一台裝置看到檔名不代表內容已完整。
