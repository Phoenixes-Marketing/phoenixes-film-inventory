param(
    [switch]$DesktopOnly,
    [switch]$StartMenuOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Updater = Join-Path $ProjectRoot "update-online-inventory.cmd"

if (-not (Test-Path $Updater)) {
    throw "Updater not found: $Updater"
}

function Join-Chars {
    param([int[]]$Codes)
    return -join ($Codes | ForEach-Object { [char]$_ })
}

$ShortcutBaseName = Join-Chars @(0x66F4, 0x65B0, 0x5C01, 0x819C, 0x5EAB, 0x5B58)
$Description = "Phoenixes Film Inventory Online Update"
$IconLocation = "$env:SystemRoot\System32\shell32.dll,167"

function New-Shortcut {
    param(
        [string]$ShortcutPath
    )

    $folder = Split-Path $ShortcutPath -Parent
    New-Item -ItemType Directory -Force -Path $folder | Out-Null

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $Updater
    $shortcut.WorkingDirectory = $ProjectRoot
    $shortcut.Description = $Description
    $shortcut.IconLocation = $IconLocation
    $shortcut.Save()
}

$created = @()

if (-not $StartMenuOnly) {
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $desktopShortcut = Join-Path $desktopPath "$ShortcutBaseName.lnk"
    New-Shortcut -ShortcutPath $desktopShortcut
    $created += $desktopShortcut
}

if (-not $DesktopOnly) {
    $programsPath = [Environment]::GetFolderPath("Programs")
    $startMenuShortcut = Join-Path $programsPath "Phoenixes\$ShortcutBaseName.lnk"
    New-Shortcut -ShortcutPath $startMenuShortcut
    $created += $startMenuShortcut
}

Write-Host "Created shortcuts:"
foreach ($path in $created) {
    Write-Host "  $path"
}
