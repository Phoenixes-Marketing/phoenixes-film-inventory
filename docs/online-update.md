# 線上庫存一鍵更新流程

## 使用方式

1. 先從 ERP 匯出最新 Excel，放到 `Z:\TO承憲\ERP\IACF`。
2. 到 `D:\封王封膜庫存監控`。
3. 雙擊 `update-online-inventory.cmd`。
4. 等視窗顯示「線上網站已顯示最新資料」。

線上網址：

`https://phoenixes-marketing.github.io/phoenixes-film-inventory/`

## 這個腳本會做什麼

- 自動讀取來源資料夾中最新的 `.xlsx`。
- 重新產生 `public\phoenixes-film-inventory\dashboard-data.js`。
- 將資料版本提交並推送到 GitHub main 分支。
- 將可瀏覽的靜態網頁推送到 GitHub Pages 的 `gh-pages` 分支。
- 檢查線上 `dashboard-data.js` 是否已經包含本次更新時間。
- 把每次更新紀錄放到 `logs` 資料夾。

## 常見狀況

- 如果 ERP Excel 沒有匯出新檔，網站仍會用來源資料夾內最新的 Excel 重新產生資料。
- 如果 GitHub Pages 剛推送完還沒更新，腳本會提示稍等 1-3 分鐘後重新整理。
- 如果出現錯誤，把視窗畫面或 `logs` 內最新紀錄傳給 Codex 即可檢查。
