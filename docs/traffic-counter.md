# 今日瀏覽次數功能

這個功能用來在庫存監控頁面顯示「今日瀏覽 N 次」。它只是輔助資訊，不能影響庫存資料、搜尋、分類、備註、採購提醒等主要功能。

## 目前植入位置

- `public\phoenixes-film-inventory\index.html`
  - 載入 `traffic-counter-config.js`
  - 在上方資訊列加入 `今日瀏覽 - 次`
  - 頁面初次渲染完成後呼叫 `recordTrafficCount()`
  - API 失敗、超時或未設定時，只維持 `-`，不阻擋庫存表載入
- `public\phoenixes-film-inventory\traffic-counter-config.js`
  - 控制是否啟用、API endpoint、timeout、debug
- `workers\traffic-counter\`
  - Cloudflare Worker + D1 的 API 範本
- `scripts\update_online_inventory.ps1`
  - GitHub Pages 發布時會一併複製 `traffic-counter-config.js`

## 前端工作原理

1. `index.html` 先照原本流程載入 `dashboard-data.js` 和 `purchase-alert-data.js`。
2. 頁面先正常渲染庫存資料。
3. `recordTrafficCount()` 讀取 `window.INVENTORY_TRAFFIC_COUNTER_CONFIG`。
4. 如果 `endpoint` 是空字串，直接跳過，只顯示 `今日瀏覽 - 次`。
5. 如果 `endpoint` 有設定，就用 `POST` 呼叫 API。
6. API 回傳 `{ count: number }` 後，前端更新成 `今日瀏覽 N 次`。
7. 如果 API 無法連線、CORS 錯誤或超過 `timeoutMs`，前端不顯示錯誤，也不影響庫存監控本體。

## API 工作原理

建議後端使用 `workers\traffic-counter` 的 Cloudflare Worker + D1：

1. Worker 收到頁面的 `POST`。
2. 用台灣時區 `Asia/Taipei` 產生今日日期，例如 `2026-07-09`。
3. 從 Cloudflare header 取得訪客 IP。
4. 用 `COUNTER_SALT + 日期 + IP` 做 SHA-256 hash，只存匿名 hash，不存原始 IP。
5. 查 D1 的 `client_cooldowns`：
   - 同一 IP 今天第一次進入，計數 +1。
   - 同一 IP 距離上次計數未滿 180 秒，不加次數。
   - 同一 IP 距離上次計數滿 180 秒，再加一次。
6. 今日總數存在 D1 的 `daily_counts`。
7. API 回傳今日總數給前端。

預設是同一 IP 冷卻 3 分鐘。如果要改成「同 IP 但不同瀏覽器也分開算」，把 `workers\traffic-counter\wrangler.toml` 裡的：

```toml
CLIENT_KEY_MODE = "ip"
```

改成：

```toml
CLIENT_KEY_MODE = "ip-browser"
```

## 部署 API

這台電腦目前沒有 Cloudflare 登入或 Token 時，不能直接部署 Worker。正式啟用需要先有 Cloudflare 帳號權限。

第一次部署流程：

```powershell
cd D:\封王封膜庫存監控\workers\traffic-counter
npx wrangler login
npx wrangler d1 create phoenixes-film-inventory-traffic
```

把上一步輸出的 `database_id` 填回 `wrangler.toml`：

```toml
database_id = "實際的 D1 database id"
```

設定匿名 hash 用的 salt：

```powershell
npx wrangler secret put COUNTER_SALT
```

套用 D1 資料表：

```powershell
npx wrangler d1 migrations apply phoenixes-film-inventory-traffic --remote
```

部署 Worker：

```powershell
npx wrangler deploy
```

部署完成後，Cloudflare 會提供類似這樣的 endpoint：

```text
https://phoenixes-film-inventory-traffic.<帳號>.workers.dev
```

把它填入：

```js
// public\phoenixes-film-inventory\traffic-counter-config.js
window.INVENTORY_TRAFFIC_COUNTER_CONFIG = {
  enabled: true,
  app: "phoenixes-film-inventory",
  endpoint: "https://phoenixes-film-inventory-traffic.<帳號>.workers.dev",
  timeoutMs: 2500,
  debug: false
};
```

然後重新執行一鍵更新或手動 commit/push，GitHub Pages 就會讀到新的 endpoint。

## 修改方式

- 改顯示文字：修改 `index.html` 裡 `traffic-count` 區塊。
- 改 API timeout：修改 `traffic-counter-config.js` 的 `timeoutMs`。
- 暫停功能：把 `traffic-counter-config.js` 的 `enabled` 改成 `false`。
- 改冷卻時間：修改 `workers\traffic-counter\wrangler.toml` 的 `COOLDOWN_SECONDS`，再重新部署 Worker。
- 改允許來源：修改 `workers\traffic-counter\wrangler.toml` 的 `ALLOWED_ORIGINS`，再重新部署 Worker。

## 移除方式

如果以後決定不要顯示今日瀏覽次數：

1. 從 `index.html` 移除 `<script src="./traffic-counter-config.js"></script>`。
2. 從 `index.html` 移除 `.traffic-count` 和 `.traffic-count-value` CSS。
3. 從上方 `.meta` 移除 `traffic-count` 這段 HTML。
4. 從 `index.html` 移除 `trafficCounterConfig()`、`renderTrafficCount()`、`recordTrafficCount()` 等相關 JS。
5. 移除底部的 `recordTrafficCount();` 呼叫。
6. 從 `scripts\update_online_inventory.ps1` 的複製清單和 deploy add 清單移除 `traffic-counter-config.js`。
7. 可選：刪除 `public\phoenixes-film-inventory\traffic-counter-config.js` 和 `workers\traffic-counter`。

## 已知限制

- 這不是精準人數統計，而是「每日使用頻率」。
- 同公司共用同一外部 IP 時，3 分鐘內可能只算一次。
- 手機網路換 IP、VPN 或刻意刷流量，仍可能造成多算。
- API 或 D1 故障時，頁面只會顯示 `-`，庫存監控本體不受影響。
