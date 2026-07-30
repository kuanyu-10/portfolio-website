# Git 安全規則

## 禁止自動執行

- `git push --force` 或任何 force push。
- `git reset --hard`。
- `git clean -fd`。
- 自動刪除 untracked 檔案。
- diverged branch 的 merge 或 rebase。
- 覆蓋本機未提交修改。
- 修改全域 Git 設定。

## 唯一自動 pull 條件

必須同時符合：

1. 使用者傳入 `-ApplySafePull`；
2. working tree clean；
3. upstream 存在；
4. local ahead = 0；
5. local behind > 0；
6. 未 diverged。

執行的命令固定為 `git pull --ff-only`。任一條件不符只回報，不改歷史。

## Stage 安全

收工腳本逐檔 stage，排除敏感檔、衝突副本、protectedPaths、超過大小上限與未知二進位檔。不使用不受控的 `git add -A`。

## Push 驗證

push 返回 0 後，仍以 `git ls-remote` 確認遠端 branch 含預期 commit。未確認不得寫 `PUSHED`。
