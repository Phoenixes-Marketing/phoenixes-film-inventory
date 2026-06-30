# 封膜庫存監控

這是一個靜態網頁面板，資料來源是 ERP 手動匯出的 Excel：

`Z:\TO承憲\ERP\IACF`

目前流程：

1. 將 ERP 分庫狀況表匯出成 `.xlsx`，放在來源資料夾。
2. 執行 `python scripts\build_dashboard.py` 更新 `public\dashboard-data.js`。
3. 用 `scripts\start_dashboard.ps1` 啟動本機預覽。

本機預覽：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start_dashboard.ps1
```

預設網址：

`http://localhost/phoenixes-film-inventory/`

同網段手機可嘗試：

`http://192.168.5.47/phoenixes-film-inventory/`

或：

`http://Phoenixes-MD/phoenixes-film-inventory/`

所有分類與庫存顏色規則記錄在：

`docs\分類與庫存規則.md`

如需讓同網段同事測試，可把 `Bind` 改成 `0.0.0.0`：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start_dashboard.ps1 -Bind 0.0.0.0 -Port 80
```

第一版只顯示五個倉：

- 台北倉
- 台中倉
- 臺南倉
- 高雄倉
- 欣凱倉
