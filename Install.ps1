# Installs (or updates) DbD Clock Overlay for the current Windows user:
# copies it to %LOCALAPPDATA%\DbD Clock Overlay, downloads the maps and perk
# icons, adds a desktop shortcut + a Start menu folder (overlay, update, read
# me, uninstall) and asks about auto-start. Run by "DbD Clock Overlay
# Setup.cmd" (which unpacks this package to a temp folder first) and, with
# -Update, by the updater. Updating keeps settings.json, the downloaded maps /
# icons and the auto-start choice, and asks nothing.
# Test switches: -Dest <folder> -LinkDir <folder> (shortcuts go there instead
# of the desktop / Start menu), -NoDownload, -AutoStart Yes|No, -StartNow Yes|No
param([string]$Dest = (Join-Path $env:LOCALAPPDATA 'DbD Clock Overlay'), [string]$LinkDir, [switch]$Update,
      [switch]$NoDownload, [ValidateSet('Ask', 'Yes', 'No')][string]$AutoStart = 'Ask', [ValidateSet('Ask', 'Yes', 'No')][string]$StartNow = 'Ask')
$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$destKey = $Dest.ToLowerInvariant()

function Ask([string]$q) {
    while ($true) { $a = Read-Host "$q (Y/N)"; if ($a -match '^\s*y') { return $true }; if ($a -match '^\s*n') { return $false } }
}

Write-Host ''
Write-Host "  DbD Clock Overlay - $(if ($Update) { 'updating' } else { 'setup' })" -ForegroundColor Cyan
Write-Host "  Folder: $Dest"
Write-Host ''

# what's running from this folder now: the overlay and/or the auto-start watcher
$running = @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object { $_.CommandLine -and $_.CommandLine.ToLowerInvariant().Contains($destKey) -and $_.ProcessId -ne $PID })
$overlayWasRunning = [bool]($running | Where-Object { $_.CommandLine -like '*ClockOverlay.ps1*' })
# auto-start is on for THIS copy when the Startup shortcut points into this folder
$startupLnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'DbD Clock Overlay watcher.lnk'
$sh = New-Object -ComObject WScript.Shell
$autoWasOn = (Test-Path $startupLnk) -and ($sh.CreateShortcut($startupLnk).Arguments.ToLowerInvariant().Contains($destKey))
# stop them so their files can be replaced
$running | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

# program files (overwritten); settings, maps and icons are left alone
New-Item -ItemType Directory -Force $Dest | Out-Null
Get-ChildItem $src -Force | ForEach-Object { Copy-Item $_.FullName $Dest -Recurse -Force }

if (-not $NoDownload) {
    if ($Update) { Write-Host 'Checking for new maps / perk icons...' -ForegroundColor Cyan; & (Join-Path $Dest 'Setup.ps1') -Installer -MissingOnly }
    else { Write-Host 'Downloading the callout maps (Hens333) and perk icons (DbD wiki)...' -ForegroundColor Cyan; & (Join-Path $Dest 'Setup.ps1') -Installer }
    Write-Host ''
}

# shortcuts: desktop + Start menu folder (an update only refreshes the ones you have)
$desk = if ($LinkDir) { $LinkDir } else { [Environment]::GetFolderPath('Desktop') }
$menu = if ($LinkDir) { Join-Path $LinkDir 'Start menu' } else { Join-Path ([Environment]::GetFolderPath('Programs')) 'DbD Clock Overlay' }
$icon = Join-Path $Dest 'overlay.ico'
function New-Link([string]$path, [string]$target, [string]$arguments, [string]$tip) {
    $l = $sh.CreateShortcut($path)
    $l.TargetPath = $target; $l.Arguments = $arguments; $l.WorkingDirectory = $Dest; $l.Description = $tip
    if (Test-Path $icon) { $l.IconLocation = "$icon,0" }
    if ($target -eq $ps) { $l.WindowStyle = 7 }   # minimised: no console flash
    $l.Save()
}
$runArgs = "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$(Join-Path $Dest 'ClockOverlay.ps1')`""
$deskLnk = Join-Path $desk 'DbD Clock Overlay.lnk'
if (-not $Update -or (Test-Path $deskLnk)) { New-Item -ItemType Directory -Force $desk | Out-Null; New-Link $deskLnk $ps $runArgs 'Start the DbD clock-callout overlay' }
if (-not $Update -or (Test-Path $menu)) {
    New-Item -ItemType Directory -Force $menu | Out-Null
    New-Link (Join-Path $menu 'DbD Clock Overlay.lnk') $ps $runArgs 'Start the DbD clock-callout overlay'
    New-Link (Join-Path $menu 'Update DbD Clock Overlay.lnk') (Join-Path $Dest 'Update.cmd') '' 'Get the newest version'
    New-Link (Join-Path $menu 'Read me.lnk') (Join-Path $Dest 'README.txt') '' 'How DbD Clock Overlay works'
    New-Link (Join-Path $menu 'Uninstall DbD Clock Overlay.lnk') (Join-Path $Dest 'Uninstall.cmd') '' 'Remove DbD Clock Overlay'
    if (-not $Update) { Write-Host 'Added a "DbD Clock Overlay" shortcut to your desktop and Start menu.' -ForegroundColor Green; Write-Host '' }
}

# auto-start: kept as it was on an update / reinstall; asked on a first install
$auto = if ($autoWasOn) { $true } elseif ($Update) { $false } else {
    switch ($AutoStart) { 'Yes' { $true } 'No' { $false } default { Ask 'Open the overlay by itself whenever you start Dead by Daylight?' } } }
if ($auto) { & (Join-Path $Dest 'AutoStart.ps1') -On }
elseif (-not $Update) { Write-Host 'OK - start it with the desktop shortcut when you play.' }
if (-not $Update) { Write-Host '' }

# start it: again if it was running before an update; asked on a first install
# (with auto-start on, the watcher starts it whenever DbD is running)
$now = if ($auto) { $false } elseif ($Update) { $overlayWasRunning } else {
    switch ($StartNow) { 'Yes' { $true } 'No' { $false } default { Ask 'Start the overlay now?' } } }
if ($now) { Start-Process $ps -ArgumentList $runArgs -WindowStyle Hidden }

if (-not $Update) {
    Write-Host 'All set. In DbD, set Display Mode to "Windowed Fullscreen".' -ForegroundColor Green
    Write-Host 'Updates: Start menu > DbD Clock Overlay > Update. To remove it: ... > Uninstall.'
    Write-Host ''
    if ($AutoStart -eq 'Ask') { [void](Read-Host 'Press Enter to close') }
}
