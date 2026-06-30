param(
  [int]$Port = 80,
  [string]$Bind = "0.0.0.0"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$PublicRoot = Join-Path $ProjectRoot "public"

python "$ProjectRoot\scripts\build_dashboard.py"
$Path = "phoenixes-film-inventory/"
$Url = if ($Port -eq 80) { "http://localhost/$Path" } else { "http://localhost:$Port/$Path" }
Write-Host "Local URL: $Url"
$HostName = [System.Net.Dns]::GetHostName()
$HostUrl = if ($Port -eq 80) { "http://$HostName/$Path" } else { "http://$HostName`:$Port/$Path" }
Write-Host "Computer-name URL: $HostUrl"
Get-NetIPAddress -AddressFamily IPv4 |
  Where-Object { $_.IPAddress -notlike '127.*' -and $_.PrefixOrigin -ne 'WellKnown' } |
  ForEach-Object {
    $LanUrl = if ($Port -eq 80) { "http://$($_.IPAddress)/$Path" } else { "http://$($_.IPAddress)`:$Port/$Path" }
    Write-Host "LAN URL: $LanUrl"
  }
Set-Location -LiteralPath $PublicRoot
python -m http.server $Port --bind $Bind
