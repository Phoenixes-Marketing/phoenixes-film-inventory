# 封王封膜庫存監控 Agent 指引

這個 repo 是 Phoenixes 封膜庫存監控系統。當使用者要求設定新電腦、更新庫存、調整儀表板或維護一鍵上傳工具時，先閱讀：

1. `README.md`
2. `docs/new-computer-setup.md`
3. `docs/online-update.md`
4. `docs/分類與庫存規則.md`

新電腦設定請優先執行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup_new_computer.ps1
```

正式更新入口是：

```cmd
update-online-inventory.cmd
```

重要原則：

- 沒有使用者明確確認「上線」、「更新」、「確認執行」或「幫我上傳」時，不要執行正式上傳或 push。
- 不要提交 Excel 暫存檔 `~$*.xlsx`。
- 不要把密碼、token、cookie、SSH private key 寫進 repo。
- 預設 ERP 匯出資料夾是 `Z:\TO承憲\ERP\IACF`。
- 預設專案資料夾是 `D:\封王封膜庫存監控`。
- GitHub Pages 正式網址是 `https://phoenixes-marketing.github.io/phoenixes-film-inventory/`。
