# 平均成本登入與 Cloudflare 管理

正式庫存網址維持不變：

`https://phoenixes-marketing.github.io/phoenixes-film-inventory/`

公開庫存仍由 GitHub Pages 提供。平均成本（未稅）不會放進 GitHub Pages 或公開 JavaScript；使用者輸入共用密碼後，瀏覽器才向 Cloudflare Worker 取得成本資料。

## Cloudflare 資源

- Worker 技術名稱：`phoenixes-film-inventory-cost`
- Worker 用途：封王封膜庫存－平均成本登入服務
- KV 中文名稱：`封王封膜庫存－平均成本資料`
- KV key：`average-cost-data`
- 原有瀏覽計數 Worker：`phoenixes-film-inventory-traffic`
- 原有瀏覽計數 D1：`phoenixes-film-inventory-traffic`

Worker 技術名稱同時會出現在 `workers.dev` 網址中。為避免改網址造成正式頁面中斷，原有計數器與新成本 Worker 都保留英數技術名稱；中文用途寫在部署訊息與本文件中。KV 名稱只供後台辨識，不影響程式綁定，因此使用中文。

## 修改共用密碼

1. 登入 Cloudflare。
2. 進入「Workers & Pages」。
3. 選擇 `phoenixes-film-inventory-cost`。
4. 進入 Settings／Bindings（設定／綁定）。
5. 找到 Variables and Secrets（變數與密鑰）。
6. 編輯 `INVENTORY_SHARED_PASSWORD`，輸入新密碼並儲存／部署。

密碼只存成 Cloudflare Secret，Git、網頁與本文件都沒有密碼值。修改密碼後，既有的 30 天解鎖會立即失效，所有裝置都要用新密碼重新登入。

`SESSION_SECRET` 是簽署 30 天登入憑證的系統密鑰，平常不要修改；若懷疑登入憑證外洩，可以更新它，讓所有裝置立即失效。

## 日常更新

把分庫狀況表、庫存異動明細表放在同一個 IACF 資料夾後，執行：

`update-online-inventory.cmd`

程式會依內容辨識兩種報表，各自選擇報表日期最新的版本：

- 有新分庫狀況表：更新公開庫存。
- 有新庫存異動明細表：更新 Cloudflare 平均成本。
- 沒有其中一份或版本相同：該部分維持原資料。
- 新成本表未涵蓋全部監控品項：停止成本更新，保留 Cloudflare 舊資料。
- 成本為 `0`：視為有效資料，顯示 `NT$0.00`。

## 安全特性與限制

- 成本 API 只接受正式 GitHub Pages 網址的瀏覽器跨來源請求。
- 密碼連續錯誤會依來源位址暫時限制嘗試次數。
- 解鎖憑證在該瀏覽器保存 30 天；不是用 IP 共享，所以每台新裝置第一次都要輸入密碼。
- 修改共用密碼或 `SESSION_SECRET` 會使舊憑證失效。
- 共用密碼無法分辨是哪一位同事，也無法阻止已取得成本的人截圖或轉傳；密碼需要定期更換並只提供給內部同事。
