# Updater: asks GitHub for the newest released version and, if it's newer than
# this one, downloads and installs it right here - settings, maps, icons and
# your auto-start choice are kept. Run by "Update.cmd" / the Start menu entry.
# -Check: only print the newest version number (the overlay uses this to show
# "update available"); installs nothing.
param([switch]$Check)
$repo = 'isJeffu/dbd-clock-overlay'
$dest = Split-Path $PSScriptRoot -Parent   # the install folder
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Get-LocalVersion { try { [version]((Get-Content (Join-Path $dest 'VERSION') -TotalCount 1).Trim()) } catch { [version]'0.0' } }
function Get-LatestRelease { Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -Headers @{ 'User-Agent' = 'DbD-Clock-Overlay-Updater' } -TimeoutSec 15 }

if ($Check) {
    try { (Get-LatestRelease).tag_name.TrimStart('v') } catch { }
    exit
}

Write-Host ''
Write-Host '  DbD Clock Overlay - updater' -ForegroundColor Cyan
Write-Host ''
$local = Get-LocalVersion
try { $rel = Get-LatestRelease }
catch { Write-Host "Couldn't reach GitHub to check for updates: $($_.Exception.Message)" -ForegroundColor Yellow; [void](Read-Host 'Press Enter to close'); exit 1 }
$latest = [version]$rel.tag_name.TrimStart('v')
if ($latest -le $local) {
    Write-Host "You have the newest version (v$local)." -ForegroundColor Green
    [void](Read-Host 'Press Enter to close'); exit
}
Write-Host "New version: v$latest (you have v$local)" -ForegroundColor Green
if ($rel.body) { Write-Host ''; Write-Host ($rel.body.Trim()); Write-Host '' }

# (GitHub rewrites spaces in file names, so match loosely: DbD-Clock-Overlay.zip)
$asset = $rel.assets | Where-Object { $_.name -match 'Overlay\.zip$' } | Select-Object -First 1
if (-not $asset) { Write-Host 'That release has no download attached - try again later.' -ForegroundColor Yellow; [void](Read-Host 'Press Enter to close'); exit 1 }
$tmp = Join-Path $env:TEMP ('dbdco-update-' + [guid]::NewGuid())
New-Item -ItemType Directory $tmp | Out-Null
try {
    Write-Host 'Downloading...'
    $zip = Join-Path $tmp 'update.zip'
    Invoke-WebRequest $asset.browser_download_url -OutFile $zip -UseBasicParsing -Headers @{ 'User-Agent' = 'DbD-Clock-Overlay-Updater' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($zip, $tmp)
    # the new version's own installer, in update mode, pointed at this folder
    $inst = Join-Path $tmp 'DbD Clock Overlay\scripts\Install.ps1'
    if (-not (Test-Path $inst)) { $inst = Join-Path $tmp 'DbD Clock Overlay\Install.ps1' }   # a package from before the scripts folder
    & $inst -Dest $dest -Update
    Write-Host "Updated to v$latest." -ForegroundColor Green
} catch {
    Write-Host "The update failed: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host 'Your current version is still there. You can also run the newest "DbD Clock Overlay Setup.cmd" by hand.'
} finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
[void](Read-Host 'Press Enter to close')
