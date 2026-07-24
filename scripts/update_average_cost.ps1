param(
    [string]$Source = "",
    [string]$DashboardData = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $OutputEncoding = [System.Text.UTF8Encoding]::new($false)
}
catch {
    # Older PowerShell hosts can ignore console encoding setup.
}

if ([string]::IsNullOrWhiteSpace($Source)) {
    $Source = "Z:\TO$([char]0x627F)$([char]0x61B2)\ERP\IACF"
}

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if ([string]::IsNullOrWhiteSpace($DashboardData)) {
    $DashboardData = Join-Path $ProjectRoot "public\phoenixes-film-inventory\dashboard-data.js"
}

$BuildScript = Join-Path $PSScriptRoot "build_average_cost.py"
$WorkerDir = Join-Path $ProjectRoot "workers\average-cost-auth"
$WorkerConfig = Join-Path $WorkerDir "wrangler.jsonc"
$Wrangler = Join-Path $WorkerDir "node_modules\.bin\wrangler.cmd"
$TempOutput = Join-Path ([System.IO.Path]::GetTempPath()) ("phoenixes-average-cost-{0}.json" -f [guid]::NewGuid().ToString("N"))
$DataKey = "average-cost-data"

function Write-CostNote {
    param([string]$Message)
    Write-Host "  $Message" -ForegroundColor DarkGray
}

function Preserve-CostData {
    param([string]$Reason)
    Write-Warning "平均成本未更新，Cloudflare 保留原有資料：$Reason"
}

function Invoke-AverageCostUpdate {
    if (-not (Test-Path -LiteralPath $BuildScript)) {
        Preserve-CostData "找不到平均成本解析程式"
        return
    }
    if (-not (Test-Path -LiteralPath $WorkerConfig)) {
        Preserve-CostData "找不到 Cloudflare Worker 設定"
        return
    }
    if (-not (Test-Path -LiteralPath $Wrangler)) {
        Preserve-CostData "這台電腦尚未安裝 Cloudflare 更新工具"
        return
    }

    $pythonCommand = Get-Command "python" -ErrorAction SilentlyContinue
    $pythonArgsPrefix = @()
    if (-not $pythonCommand) {
        $pythonCommand = Get-Command "py" -ErrorAction SilentlyContinue
        $pythonArgsPrefix = @("-3")
    }
    if (-not $pythonCommand) {
        Preserve-CostData "找不到 Python"
        return
    }

    $pythonArgs = $pythonArgsPrefix + @(
        $BuildScript,
        "--source", $Source,
        "--dashboard", $DashboardData,
        "--output", $TempOutput
    )
    & $pythonCommand.Source @pythonArgs
    $buildExitCode = $LASTEXITCODE
    if ($buildExitCode -eq 3) {
        Write-CostNote "未找到庫存異動明細表；平均成本維持原樣。"
        return
    }
    if ($buildExitCode -ne 0 -or -not (Test-Path -LiteralPath $TempOutput)) {
        Preserve-CostData "新的庫存異動明細表未通過驗證"
        return
    }

    $newData = Get-Content -LiteralPath $TempOutput -Encoding UTF8 -Raw | ConvertFrom-Json
    $savedErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $remoteText = & $Wrangler kv key get $DataKey --binding COST_DATA --remote --config $WorkerConfig 2>$null
    $remoteExitCode = $LASTEXITCODE
    $ErrorActionPreference = $savedErrorActionPreference
    if ($remoteExitCode -eq 0 -and -not ([string]::IsNullOrWhiteSpace(($remoteText -join "`n")))) {
        $remoteData = ($remoteText -join "`n") | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($null -eq $remoteData) {
            Write-CostNote "Cloudflare 尚無可比較的平均成本版本，準備上傳。"
        }
        elseif (
            $remoteData.source.sha256 -and
            $remoteData.source.sha256 -eq $newData.source.sha256
        ) {
            Write-CostNote "庫存異動明細表沒有新版本；平均成本維持原樣。"
            return
        }
    }
    elseif ($remoteExitCode -ne 0) {
        Write-CostNote "Cloudflare 尚無平均成本版本，準備第一次上傳。"
    }

    & $Wrangler kv key put $DataKey --path $TempOutput --binding COST_DATA --remote --config $WorkerConfig
    if ($LASTEXITCODE -ne 0) {
        Preserve-CostData "Cloudflare 上傳失敗"
        return
    }

    Write-Host "[OK] 平均成本已更新到 Cloudflare" -ForegroundColor Green
    Write-CostNote "來源：$($newData.source.filename)"
    Write-CostNote "報表日期：$($newData.source.reportDate)"
    Write-CostNote "符合品項：$($newData.summary.matchedItemCount)/$($newData.summary.dashboardItemCount)"
    Write-CostNote "成本為 0：$($newData.summary.zeroCostCount)"
}

try {
    Invoke-AverageCostUpdate
}
catch {
    Preserve-CostData $_.Exception.Message
}

$resolvedTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$resolvedTempOutput = [System.IO.Path]::GetFullPath($TempOutput)
if (
    $resolvedTempOutput.StartsWith($resolvedTempRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
    (Test-Path -LiteralPath $resolvedTempOutput)
) {
    Remove-Item -LiteralPath $resolvedTempOutput -Force
}
