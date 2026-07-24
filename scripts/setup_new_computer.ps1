param(
    [string]$Source = "",
    [switch]$SkipPipInstall,
    [switch]$SkipCloudflareSetup,
    [switch]$SkipShortcut,
    [switch]$NoSourceCheck
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

function Join-Chars {
    param([int[]]$Codes)
    return -join ($Codes | ForEach-Object { [char]$_ })
}

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
        throw "Command not found: $Name"
    }

    return $command
}

function Invoke-Checked {
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

function Get-GitOutput {
    param([string[]]$Arguments)

    $output = & git -C $ProjectRoot @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Git command failed: git -C $ProjectRoot $($Arguments -join ' ')"
    }

    return $output
}

$DefaultSource = "Z:\TO$([char]0x627F)$([char]0x61B2)\ERP\IACF"
if ([string]::IsNullOrWhiteSpace($Source)) {
    $Source = $DefaultSource
}

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$RepoUrlSsh = "git@github.com:Phoenixes-Marketing/phoenixes-film-inventory.git"
$RepoUrlHttps = "https://github.com/Phoenixes-Marketing/phoenixes-film-inventory.git"
$RequirementsFile = Join-Path $ProjectRoot "requirements.txt"
$Updater = Join-Path $ProjectRoot "update-online-inventory.cmd"
$UpdateScript = Join-Path $ProjectRoot "scripts\update_online_inventory.ps1"
$ShortcutScript = Join-Path $ProjectRoot "scripts\create_shortcuts.ps1"
$PurchaseAlertSettingsName = Join-Chars @(0x63A1, 0x8CFC, 0x63D0, 0x9192, 0x8A2D, 0x5B9A)
$PurchaseAlertSettingsFile = Join-Path $ProjectRoot "data\$PurchaseAlertSettingsName.xlsx"
$AverageCostWorkerDir = Join-Path $ProjectRoot "workers\average-cost-auth"
$AverageCostWorkerPackage = Join-Path $AverageCostWorkerDir "package.json"

Write-Host "Phoenixes Film Inventory - New Computer Setup" -ForegroundColor White
Write-Note "Project folder: $ProjectRoot"

Write-Step "Checking required commands"
Require-Command -Name "git" | Out-Null
$pythonCommand = Get-Command "python" -ErrorAction SilentlyContinue
$pythonArgsPrefix = @()
if (-not $pythonCommand) {
    $pythonCommand = Require-Command -Name "py"
    $pythonArgsPrefix = @("-3")
}
Require-Command -Name "powershell" | Out-Null
Write-Ok "Required commands are available"

Write-Step "Checking repository"
$insideWorkTree = (& git -C $ProjectRoot rev-parse --is-inside-work-tree 2>$null)
if ($LASTEXITCODE -ne 0 -or $insideWorkTree -ne "true") {
    throw "This folder is not a Git repository. Clone the repo first: $RepoUrlSsh"
}

$remoteNames = @(Get-GitOutput -Arguments @("remote"))
if ($remoteNames -notcontains "github") {
    if ($remoteNames -contains "origin") {
        $originUrl = (Get-GitOutput -Arguments @("remote", "get-url", "origin") | Select-Object -First 1)
        Invoke-Checked -Command "git" -Arguments @("-C", $ProjectRoot, "remote", "add", "github", $originUrl)
        Write-Ok "Added github remote from origin: $originUrl"
    }
    else {
        Invoke-Checked -Command "git" -Arguments @("-C", $ProjectRoot, "remote", "add", "github", $RepoUrlSsh)
        Write-Ok "Added github remote: $RepoUrlSsh"
    }
}
else {
    $githubUrl = (Get-GitOutput -Arguments @("remote", "get-url", "github") | Select-Object -First 1)
    Write-Ok "github remote exists: $githubUrl"
}

Write-Step "Checking project files"
foreach ($path in @($RequirementsFile, $Updater, $UpdateScript, $ShortcutScript, $PurchaseAlertSettingsFile, $AverageCostWorkerPackage)) {
    if (-not (Test-Path $path)) {
        throw "Missing required project file: $path"
    }
}
Write-Ok "Project files are present"

if (-not $SkipPipInstall) {
    Write-Step "Installing Python packages"
    $pipArgs = $pythonArgsPrefix + @("-m", "pip", "install", "-r", $RequirementsFile)
    Invoke-Checked -Command $pythonCommand.Source -Arguments $pipArgs -WorkingDirectory $ProjectRoot
    Write-Ok "Python packages installed"
}
else {
    Write-Note "Python package installation skipped"
}

Write-Step "Verifying Python packages"
$verifyArgs = $pythonArgsPrefix + @("-c", "import python_calamine, openpyxl; print('python packages OK')")
Invoke-Checked -Command $pythonCommand.Source -Arguments $verifyArgs -WorkingDirectory $ProjectRoot
Write-Ok "Python packages can be imported"

if (-not $SkipCloudflareSetup) {
    Write-Step "Installing Cloudflare average cost updater"
    Require-Command -Name "node" | Out-Null
    $npmCommand = Get-Command "npm.cmd" -ErrorAction SilentlyContinue
    if (-not $npmCommand) {
        $npmCommand = Require-Command -Name "npm"
    }
    Invoke-Checked -Command $npmCommand.Source -Arguments @("install") -WorkingDirectory $AverageCostWorkerDir
    $wrangler = Join-Path $AverageCostWorkerDir "node_modules\.bin\wrangler.cmd"
    if (-not (Test-Path -LiteralPath $wrangler)) {
        throw "Cloudflare updater was not installed: $wrangler"
    }
    Write-Ok "Cloudflare update tool installed"

    & $wrangler whoami
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "Cloudflare login is ready"
    }
    else {
        Write-Note "Cloudflare is not signed in yet. Run this once before updating average cost:"
        Write-Note "$wrangler login"
    }
}
else {
    Write-Note "Cloudflare average cost updater setup skipped"
}

if (-not $NoSourceCheck) {
    Write-Step "Checking ERP Excel source folder"
    if (-not (Test-Path $Source)) {
        throw "ERP source folder not found: $Source"
    }

    $excelFiles = @(Get-ChildItem -LiteralPath $Source -Filter "*.xlsx" -File | Where-Object { -not $_.Name.StartsWith("~$") })
    if ($excelFiles.Count -eq 0) {
        Write-Note "Source folder exists, but no .xlsx files were found yet. Export ERP report before uploading."
    }
    else {
        $latest = $excelFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        Write-Ok "ERP source folder is available"
        Write-Note "Latest Excel: $($latest.Name)"
    }
}
else {
    Write-Note "ERP source folder check skipped"
}

if (-not $SkipShortcut) {
    Write-Step "Creating desktop and Start Menu shortcuts"
    Invoke-Checked -Command "powershell" -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $ShortcutScript) -WorkingDirectory $ProjectRoot
    Write-Ok "Shortcuts created"
}
else {
    Write-Note "Shortcut creation skipped"
}

Write-Step "Done"
Write-Ok "This computer is ready to update the online inventory dashboard."
Write-Note "Export the ERP Excel report to: $Source"
Write-Note "Then run: $Updater"
Write-Note "If Git push fails, sign in or configure GitHub SSH/HTTPS credentials for this repo."
Write-Note "If average cost stays unchanged, confirm this computer is signed in to Cloudflare."
