# 新電腦設定與交接指南

這份文件給未來的你、同事，或另一台電腦上的 AI 使用。目標是讓新電腦也能做到：

1. 從 ERP 匯出 Excel 到指定資料夾。
2. 雙擊 `update-online-inventory.cmd`。
3. 自動讀取最新 Excel、更新採購提醒資料、提交 GitHub，並發布到 GitHub Pages。

正式網站：

`https://phoenixes-marketing.github.io/phoenixes-film-inventory/`

GitHub repo：

`git@github.com:Phoenixes-Marketing/phoenixes-film-inventory.git`

HTTPS 備用網址：

`https://github.com/Phoenixes-Marketing/phoenixes-film-inventory.git`

## 新電腦必要條件

- Windows 電腦。
- 能連到 ERP 匯出資料夾，預設為 `Z:\TO承憲\ERP\IACF`。
- 已安裝 Git。
- 已安裝 Python 3。
- 已安裝 Node.js（用於更新 Cloudflare 上的平均成本）。
- 這台電腦的 Git 有權限 push 到 `Phoenixes-Marketing/phoenixes-film-inventory`。
- 可以執行 PowerShell 腳本。

Python 套件記錄在：

`requirements.txt`

目前需要：

- `python-calamine==0.7.0`：快速讀取 Excel。
- `openpyxl>=3.1,<4`：建立/維護採購提醒 Excel 模板。

## 建議安裝流程

建議把專案放在：

`D:\封王封膜庫存監控`

用 SSH clone：

```powershell
git clone git@github.com:Phoenixes-Marketing/phoenixes-film-inventory.git D:\封王封膜庫存監控
cd /d D:\封王封膜庫存監控
```

如果這台電腦只設定 HTTPS GitHub 登入，也可以：

```powershell
git clone https://github.com/Phoenixes-Marketing/phoenixes-film-inventory.git D:\封王封膜庫存監控
cd /d D:\封王封膜庫存監控
```

接著執行初始化腳本：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup_new_computer.ps1
```

這支腳本會做：

- 檢查 Git、Python、PowerShell。
- 確認目前資料夾是 Git repo。
- 確認或建立 `github` remote。
- 安裝 `requirements.txt` 內的 Python 套件。
- 安裝平均成本 Worker 所需的 Cloudflare 更新工具。
- 檢查採購提醒設定檔是否存在。
- 檢查 ERP 來源資料夾是否能讀取。
- 建立桌面與開始功能表捷徑。

如果新電腦暫時無法連到 `Z:`，可以先跳過來源資料夾檢查：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup_new_computer.ps1 -NoSourceCheck
```

如果 Python 套件已經安裝好，可以跳過 pip：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup_new_computer.ps1 -SkipPipInstall
```

如果這台電腦只需要更新公開庫存、不需要更新平均成本，可以跳過 Cloudflare 工具：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup_new_computer.ps1 -SkipCloudflareSetup
```

## GitHub 權限設定

一鍵更新需要能 push 到 GitHub。

如果用 SSH，請確認：

```powershell
ssh -T git@github.com
git remote -v
```

repo 需要有一個叫 `github` 的 remote。初始化腳本會自動處理：

- 如果已經有 `github`，沿用。
- 如果只有 `origin`，就把 `origin` 的網址複製成 `github`。
- 如果兩者都沒有，就加上 SSH repo URL。

如果之後一鍵更新時卡在 GitHub 登入，代表這台電腦還沒有完成 GitHub 認證。請先設定 SSH key，或用 HTTPS 登入 GitHub。

## ERP 來源資料夾

預設來源：

`Z:\TO承憲\ERP\IACF`

一鍵更新會讀取 Excel 內容來辨識「分庫狀況表」與「庫存異動明細表」，各自選擇報表日期最新的版本，並排除 Excel 暫存檔 `~$*.xlsx`。兩份報表不必同時存在。

如果新電腦的網路磁碟代號不同，先建議把公司共用資料夾掛成同樣的 `Z:`。如果短期內真的不同，也可以直接指定來源：

```powershell
.\update-online-inventory.cmd -Source "X:\你的ERP匯出資料夾"
```

## 日常使用流程

1. 從 ERP 匯出要更新的分庫狀況表或庫存異動明細表 Excel。
2. 放到 `Z:\TO承憲\ERP\IACF`。
3. 雙擊桌面或開始功能表的「更新封膜庫存」捷徑。
4. 等視窗顯示完成。
5. 打開正式網站確認：

`https://phoenixes-marketing.github.io/phoenixes-film-inventory/`

## 重要檔案

- `update-online-inventory.cmd`：給使用者雙擊的一鍵更新入口。
- `scripts\update_online_inventory.ps1`：實際更新、提交與發布 GitHub Pages。
- `scripts\setup_new_computer.ps1`：新電腦初始化腳本。
- `scripts\create_shortcuts.ps1`：建立桌面與開始功能表捷徑。
- `scripts\build_dashboard.py`：讀 ERP Excel 並產生庫存資料。
- `scripts\build_purchase_alerts.py`：讀採購提醒設定 Excel 並產生提醒資料。
- `scripts\build_average_cost.py`：讀庫存異動明細表並產生平均成本資料。
- `scripts\update_average_cost.ps1`：比較並更新 Cloudflare 上的平均成本。
- `workers\average-cost-auth`：密碼驗證與平均成本 API。
- `data\採購提醒設定.xlsx`：安全量與採購提醒條件設定。
- `public\phoenixes-film-inventory\dashboard-data.js`：目前庫存資料。
- `public\phoenixes-film-inventory\purchase-alert-data.js`：目前採購提醒設定資料。

## 給未來 AI 的任務說明

如果使用者說「我要讓這台電腦也能更新庫存監控系統」，請照下面順序處理：

1. 確認這台電腦是 Windows。
2. 安裝或確認 Git、Python。
3. clone repo 到 `D:\封王封膜庫存監控`，或使用使用者指定資料夾。
4. 在 repo 內執行 `scripts\setup_new_computer.ps1`。
5. 確認 `git remote -v` 有 `github`。
6. 確認 `python -c "import python_calamine, openpyxl"` 成功。
7. 確認能讀到 `Z:\TO承憲\ERP\IACF`，或詢問使用者實際 ERP 匯出路徑。
8. 建立捷徑。
9. 不要在沒有使用者確認的情況下執行正式上傳。

正式上傳只有在使用者明確說「上線」、「更新」、「確認執行」或「幫我上傳」時才執行。
