# Removes DbD Clock Overlay: turns auto-start off, closes the overlay, deletes
# the desktop / Start menu shortcuts, then this whole folder (settings, maps,
# icons and logs included). Run by "Uninstall.cmd" / the Start menu entry.
# Test switches: -LinkDir <folder> (where Install.ps1 put the shortcuts),
# -Yes (don't ask), -KeepAutoStart (leave the Startup folder alone)
param([string]$LinkDir, [switch]$Yes, [switch]$KeepAutoStart)
$dest = Split-Path $PSScriptRoot -Parent   # the install folder

Write-Host ''
Write-Host '  DbD Clock Overlay - uninstall' -ForegroundColor Cyan
Write-Host "  This deletes $dest and its shortcuts."
Write-Host ''
if (-not $Yes) {
    while ($true) { $a = Read-Host 'Remove DbD Clock Overlay? (Y/N)'; if ($a -match '^\s*n') { exit }; if ($a -match '^\s*y') { break } }
}

if (-not $KeepAutoStart) { & (Join-Path $PSScriptRoot 'AutoStart.ps1') -Off }
# close this install's overlay (and anything else running from this folder)
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object { $_.CommandLine -and $_.CommandLine.ToLowerInvariant().Contains($dest.ToLowerInvariant()) -and $_.ProcessId -ne $PID } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

$desk = if ($LinkDir) { $LinkDir } else { [Environment]::GetFolderPath('Desktop') }
$menu = if ($LinkDir) { Join-Path $LinkDir 'Start menu' } else { Join-Path ([Environment]::GetFolderPath('Programs')) 'DbD Clock Overlay' }
Remove-Item (Join-Path $desk 'DbD Clock Overlay.lnk') -Force -ErrorAction SilentlyContinue   # (the menu folder also holds "Update")
Remove-Item $menu -Recurse -Force -ErrorAction SilentlyContinue

# the folder goes a few seconds after this window closes (it can't delete
# itself while it's running from inside it)
Start-Process (Join-Path $env:SystemRoot 'System32\cmd.exe') -ArgumentList '/c', "ping -n 5 127.0.0.1 >nul & rd /s /q `"$dest`"" -WindowStyle Hidden -WorkingDirectory $env:TEMP
Write-Host 'Removed. The folder disappears a few seconds after this window closes.' -ForegroundColor Green
if (-not $Yes) { [void](Read-Host 'Press Enter to close') }
