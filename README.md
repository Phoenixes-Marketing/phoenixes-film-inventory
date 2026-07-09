# 封王封膜庫存監控

這是一個靜態網頁面板，資料來源是 ERP 手動匯出的 Excel：

`Z:\TO承憲\ERP\IACF`

正式網站使用 GitHub Pages 上線：

`https://phoenixes-marketing.github.io/phoenixes-film-inventory/`

目前流程：

1. 將 ERP 分庫狀況表匯出成 `.xlsx`，放在來源資料夾。
2. 執行 `python scripts\build_dashboard.py` 更新 `public\phoenixes-film-inventory\dashboard-data.js`。
3. 用 `scripts\start_dashboard.ps1` 啟動本機預覽。

線上更新：

1. 將 ERP 分庫狀況表匯出成 `.xlsx`，放在來源資料夾。
2. 雙擊 `update-online-inventory.cmd`。
3. 等視窗顯示「線上網站已顯示最新資料」。

詳細一鍵更新流程：

`docs\online-update.md`

新電腦設定與交接指南：

`docs\new-computer-setup.md`

在新電腦 clone repo 後，可執行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup_new_computer.ps1
```

如需重建桌面與開始功能表捷徑：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\create_shortcuts.ps1
```

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

今日瀏覽次數功能與 API 設定記錄在：

`docs\traffic-counter.md`

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

核心檔案：

- `public\phoenixes-film-inventory\index.html`：監控儀表板頁面
- `public\phoenixes-film-inventory\dashboard-data.js`：目前上線資料
- `public\phoenixes-film-inventory\traffic-counter-config.js`：今日瀏覽次數 API 設定
- `workers\traffic-counter`：今日瀏覽次數 Cloudflare Worker + D1 範本
- `scripts\build_dashboard.py`：讀取 ERP Excel 並產生資料
- `scripts\update_online_inventory.ps1`：一鍵更新與上傳 GitHub Pages
- `scripts\setup_new_computer.ps1`：新電腦初始化與環境檢查
- `update-online-inventory.cmd`：給使用者雙擊的更新入口
- `docs\分類與庫存規則.md`：分類與庫存顏色規則
- `docs\traffic-counter.md`：今日瀏覽次數植入、部署、修改與移除說明
