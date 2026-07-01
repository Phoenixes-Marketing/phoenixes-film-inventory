param(
    [string]$Source = "",
    [switch]$NoOpen,
    [switch]$SkipVerify
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

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
$PublicRoot = Join-Path $ProjectRoot "public"
$PublicAppDir = Join-Path $PublicRoot "phoenixes-film-inventory"
$DataFile = Join-Path $PublicAppDir "dashboard-data.js"
$PurchaseAlertDataFile = Join-Path $PublicAppDir "purchase-alert-data.js"
$BuildScript = Join-Path $ProjectRoot "scripts\build_dashboard.py"
$PurchaseAlertBuildScript = Join-Path $ProjectRoot "scripts\build_purchase_alerts.py"
$PurchaseAlertSettingsName = [string][char]0x63A1 + [string][char]0x8CFC + [string][char]0x63D0 + [string][char]0x9192 + [string][char]0x8A2D + [string][char]0x5B9A + ".xlsx"
$PurchaseAlertSettingsRelativePath = "data/$PurchaseAlertSettingsName"
$PurchaseAlertSettingsFile = Join-Path $ProjectRoot ("data\$PurchaseAlertSettingsName")
$DeployDir = Join-Path $ProjectRoot ".deploy\gh-pages"
$LogDir = Join-Path $ProjectRoot "logs"
$LiveUrl = "https://phoenixes-marketing.github.io/phoenixes-film-inventory/"

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogPath = Join-Path $LogDir ("online-update-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
$TranscriptStarted = $false

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "== $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Note {
    param([string]$Message)
    Write-Host "  $Message" -ForegroundColor DarkGray
}

function Require-Command {
    param([string]$Name)

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "Command not found: $Name. Please install it or confirm PATH."
    }

    return $command
}

function Invoke-External {
    param(
        [string]$Command,
        [string[]]$Arguments,
        [string]$WorkingDirectory = $ProjectRoot
    )

    Push-Location $WorkingDirectory
    try {
        & $Command @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed: $Command $($Arguments -join ' ')"
        }
    }
    finally {
        Pop-Location
    }
}

function Invoke-Git {
    param(
        [string[]]$Arguments,
        [string]$WorkingDirectory = $ProjectRoot
    )

    Invoke-External -Command "git" -Arguments (@("-C", $WorkingDirectory) + $Arguments) -WorkingDirectory $ProjectRoot
}

function Get-GitOutput {
    param(
        [string[]]$Arguments,
        [string]$WorkingDirectory = $ProjectRoot
    )

    $output = & git -C $WorkingDirectory @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Git command failed: git -C $WorkingDirectory $($Arguments -join ' ')"
    }

    return $output
}

function Test-GitRef {
    param([string]$Ref)

    & git -C $ProjectRoot rev-parse --verify --quiet $Ref *> $null
    return $LASTEXITCODE -eq 0
}

function Read-DashboardData {
    param([string]$Path)

    $content = Get-Content -LiteralPath $Path -Encoding UTF8 -Raw
    $prefix = "window.INVENTORY_DASHBOARD_DATA = "
    if (-not $content.StartsWith($prefix)) {
        throw "dashboard-data.js has an unexpected format."
    }

    $json = $content.Substring($prefix.Length).Trim()
    if ($json.EndsWith(";")) {
        $json = $json.Substring(0, $json.Length - 1)
    }

    return $json | ConvertFrom-Json
}

function Read-PurchaseAlertData {
    param([string]$Path)

    $content = Get-Content -LiteralPath $Path -Encoding UTF8 -Raw
    $prefix = "window.PURCHASE_ALERT_SETTINGS = "
    if (-not $content.StartsWith($prefix)) {
        throw "purchase-alert-data.js has an unexpected format."
    }

    $json = $content.Substring($prefix.Length).Trim()
    if ($json.EndsWith(";")) {
        $json = $json.Substring(0, $json.Length - 1)
    }

    return $json | ConvertFrom-Json
}

function Ensure-DeployWorktree {
    Write-Step "Preparing GitHub Pages deploy folder"
    Invoke-Git -Arguments @("fetch", "github", "gh-pages")

    if (Test-Path $DeployDir) {
        $gitPointer = Join-Path $DeployDir ".git"
        if (-not (Test-Path $gitPointer)) {
            throw "$DeployDir exists, but it is not a Git worktree. Please inspect it first."
        }

        Invoke-Git -Arguments @("pull", "--ff-only", "github", "gh-pages") -WorkingDirectory $DeployDir
        Write-Ok "Deploy folder is up to date"
        return
    }

    New-Item -ItemType Directory -Force -Path (Split-Path $DeployDir -Parent) | Out-Null
    if (Test-GitRef -Ref "gh-pages") {
        Invoke-Git -Arguments @("worktree", "add", $DeployDir, "gh-pages")
    }
    else {
        Invoke-Git -Arguments @("worktree", "add", "-b", "gh-pages", $DeployDir, "github/gh-pages")
    }

    Write-Ok "Deploy folder is ready"
}

function Copy-PublicFilesToDeploy {
    Write-Step "Preparing static files for GitHub Pages"

    $copyMap = @(
        @{ From = (Join-Path $PublicAppDir "index.html"); To = "index.html" },
        @{ From = $DataFile; To = "dashboard-data.js" },
        @{ From = $PurchaseAlertDataFile; To = "purchase-alert-data.js" },
        @{ From = (Join-Path $PublicRoot "robots.txt"); To = "robots.txt" },
        @{ From = (Join-Path $PublicRoot "favicon.svg"); To = "favicon.svg" }
    )

    foreach ($item in $copyMap) {
        if (-not (Test-Path $item.From)) {
            throw "Missing deploy file: $($item.From)"
        }
        Copy-Item -LiteralPath $item.From -Destination (Join-Path $DeployDir $item.To) -Force
    }

    Set-Content -LiteralPath (Join-Path $DeployDir ".nojekyll") -Value "" -Encoding UTF8 -NoNewline
    Set-Content -LiteralPath (Join-Path $DeployDir "README.md") -Encoding UTF8 -Value @"
# Phoenixes Film Inventory

Static GitHub Pages deployment for the Phoenixes film inventory dashboard.

Live URL:
$LiveUrl
"@

    Write-Ok "Static files are ready"
}

function Commit-And-Push-MainIfNeeded {
    param([string]$CommitMessage)

    Write-Step "Saving inventory data version"
    $dataPaths = @(
        "public/phoenixes-film-inventory/dashboard-data.js",
        "public/phoenixes-film-inventory/purchase-alert-data.js",
        $PurchaseAlertSettingsRelativePath
    )
    $changes = @(Get-GitOutput -Arguments (@("status", "--porcelain", "--") + $dataPaths))
    if ($changes.Count -eq 0) {
        Write-Note "No inventory data change on main; skipping main commit."
        return
    }

    Invoke-Git -Arguments (@("add") + $dataPaths)
    Invoke-Git -Arguments @("commit", "-m", $CommitMessage)
    Invoke-Git -Arguments @("push", "github", "main")
    Write-Ok "Main branch backup pushed"
}

function Commit-And-Push-DeployIfNeeded {
    param([string]$CommitMessage)

    Write-Step "Publishing GitHub Pages"
    $changes = @(Get-GitOutput -Arguments @("status", "--porcelain") -WorkingDirectory $DeployDir)
    if ($changes.Count -eq 0) {
        Write-Note "No GitHub Pages file change; skipping deploy commit."
        return
    }

    Invoke-Git -Arguments @("add", "index.html", "dashboard-data.js", "purchase-alert-data.js", "robots.txt", "favicon.svg", ".nojekyll", "README.md") -WorkingDirectory $DeployDir
    Invoke-Git -Arguments @("commit", "-m", $CommitMessage) -WorkingDirectory $DeployDir
    Invoke-Git -Arguments @("push", "github", "gh-pages") -WorkingDirectory $DeployDir
    Write-Ok "GitHub Pages pushed"
}

function Verify-LiveData {
    param(
        [string]$GeneratedAt,
        [string]$PurchaseAlertGeneratedAt = ""
    )

    if ($SkipVerify) {
        Write-Note "Live verification skipped."
        return
    }

    Write-Step "Verifying live website"
    $verified = $false
    for ($attempt = 1; $attempt -le 12; $attempt++) {
        try {
            $cacheBust = [guid]::NewGuid().ToString("N")
            $dataUrl = "$($LiveUrl)dashboard-data.js?check=$cacheBust"
            $purchaseUrl = "$($LiveUrl)purchase-alert-data.js?check=$cacheBust"
            $response = Invoke-WebRequest -Uri $dataUrl -UseBasicParsing -TimeoutSec 15
            $purchaseResponse = Invoke-WebRequest -Uri $purchaseUrl -UseBasicParsing -TimeoutSec 15
            $purchaseVerified = [string]::IsNullOrWhiteSpace($PurchaseAlertGeneratedAt) -or $purchaseResponse.Content.Contains($PurchaseAlertGeneratedAt)
            if ($response.StatusCode -eq 200 -and $response.Content.Contains($GeneratedAt) -and $purchaseResponse.StatusCode -eq 200 -and $purchaseVerified) {
                $verified = $true
                break
            }
        }
        catch {
            Write-Note "Attempt $attempt did not verify yet; retrying."
        }

        if ($attempt -lt 12) {
            Start-Sleep -Seconds 10
        }
    }

    if ($verified) {
        Write-Ok "Live website shows the latest dashboard and purchase alert data"
    }
    else {
        Write-Warning "Push completed, but GitHub Pages may still be refreshing. Please refresh the site in 1-3 minutes."
    }
}

try {
    Start-Transcript -Path $LogPath -Append | Out-Null
    $TranscriptStarted = $true

    Write-Host "Phoenixes Film Inventory - Online Update" -ForegroundColor White
    Write-Note "Project folder: $ProjectRoot"
    Write-Note "Log file: $LogPath"

    Write-Step "Checking environment"
    Require-Command -Name "git" | Out-Null
    $pythonCommand = Get-Command "python" -ErrorAction SilentlyContinue
    $pythonArgsPrefix = @()
    if (-not $pythonCommand) {
        $pythonCommand = Require-Command -Name "py"
        $pythonArgsPrefix = @("-3")
    }
    Require-Command -Name "powershell" | Out-Null
    if (-not (Test-Path $Source)) {
        throw "ERP Excel folder not found: $Source"
    }
    if (-not (Test-Path $BuildScript)) {
        throw "Build script not found: $BuildScript"
    }
    if (-not (Test-Path $PurchaseAlertBuildScript)) {
        throw "Purchase alert build script not found: $PurchaseAlertBuildScript"
    }
    if (-not (Test-Path $PurchaseAlertSettingsFile)) {
        throw "Purchase alert settings file not found: $PurchaseAlertSettingsFile"
    }
    Get-GitOutput -Arguments @("remote", "get-url", "github") | Out-Null
    Write-Ok "Environment check passed"

    Write-Step "Reading ERP Excel and building dashboard data"
    $pythonArgs = $pythonArgsPrefix + @($BuildScript, "--source", $Source, "--output", $DataFile)
    Invoke-External -Command $pythonCommand.Source -Arguments $pythonArgs -WorkingDirectory $ProjectRoot
    $dashboardData = Read-DashboardData -Path $DataFile
    Write-Ok "dashboard-data.js generated"
    Write-Note "Source Excel: $($dashboardData.source.filename)"
    Write-Note "Report date: $($dashboardData.source.reportDates -join ', ')"
    Write-Note "Item count: $($dashboardData.summary.itemCount)"
    Write-Note "Generated at: $($dashboardData.generatedAt)"

    Write-Step "Reading purchase alert settings"
    $purchaseArgs = $pythonArgsPrefix + @($PurchaseAlertBuildScript, "--source", $PurchaseAlertSettingsFile, "--output", $PurchaseAlertDataFile)
    Invoke-External -Command $pythonCommand.Source -Arguments $purchaseArgs -WorkingDirectory $ProjectRoot
    $purchaseAlertData = Read-PurchaseAlertData -Path $PurchaseAlertDataFile
    Write-Ok "purchase-alert-data.js generated"
    Write-Note "Configured alerts: $($purchaseAlertData.summary.configuredCount)"
    Write-Note "Enabled configured alerts: $($purchaseAlertData.summary.enabledConfiguredCount)"
    Write-Note "Generated at: $($purchaseAlertData.generatedAt)"

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
    $commitMessage = "Update inventory data $timestamp"

    Commit-And-Push-MainIfNeeded -CommitMessage $commitMessage
    Ensure-DeployWorktree
    Copy-PublicFilesToDeploy
    Commit-And-Push-DeployIfNeeded -CommitMessage $commitMessage
    Verify-LiveData -GeneratedAt ([string]$dashboardData.generatedAt) -PurchaseAlertGeneratedAt ([string]$purchaseAlertData.generatedAt)

    Write-Step "Done"
    Write-Ok "Live URL: $LiveUrl"
    if (-not $NoOpen) {
        Start-Process $LiveUrl
    }
}
catch {
    Write-Host ""
    Write-Host "Update failed:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Log file: $LogPath" -ForegroundColor Yellow
    exit 1
}
finally {
    if ($TranscriptStarted) {
        Stop-Transcript | Out-Null
    }
}
