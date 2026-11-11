# Turns the auto-start on or off: "AutoStart.ps1 -On" / "AutoStart.ps1 -Off"
param([switch]$On, [switch]$Off)
$startup = [Environment]::GetFolderPath('Startup')
$lnkPath = Join-Path $startup 'DbD Clock Overlay watcher.lnk'
$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$watcher = Join-Path $PSScriptRoot 'Watcher.ps1'
# conhost --headless: no window. Plain powershell -WindowStyle Hidden still shows one
# where Windows Terminal is the default terminal (Windows 11), and closing it stops the watcher.
$hc = Join-Path $env:SystemRoot 'System32\conhost.exe'

if ($On) {
    $sh = New-Object -ComObject WScript.Shell
    $lnk = $sh.CreateShortcut($lnkPath)
    $lnk.TargetPath = $hc
    $lnk.Arguments = "--headless `"$ps`" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$watcher`""
    $lnk.WorkingDirectory = $PSScriptRoot
    $lnk.WindowStyle = 7
    $lnk.Save()
    Start-Process $hc -ArgumentList '--headless', "`"$ps`"", '-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', "`"$watcher`"" -WindowStyle Hidden
    Write-Host 'Auto-start is ON: the overlay will open whenever Dead by Daylight is running.' -ForegroundColor Green
}
if ($Off) {
    if (Test-Path $lnkPath) { Remove-Item $lnkPath }
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
        Where-Object { $_.CommandLine -like '*Watcher.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }
    Write-Host 'Auto-start is OFF. Use "2 - Start overlay" to run it by hand.' -ForegroundColor Yellow
}
