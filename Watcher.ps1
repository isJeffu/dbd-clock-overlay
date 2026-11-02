# Auto-start watcher: runs quietly from the Windows Startup folder and starts
# the overlay whenever Dead by Daylight is running. It only checks the process
# list every 5 seconds - no screenshots, nothing else. The overlay closes itself
# when the game closes. Remove with "Remove auto-start.cmd".

$createdNew = $false
$watcherMutex = New-Object System.Threading.Mutex($true, 'Local\DbdClockOverlayWatcher', [ref]$createdNew)
if (-not $createdNew) { exit }   # already watching

$overlay = Join-Path $PSScriptRoot 'ClockOverlay.ps1'
$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

while ($true) {
    if (Get-Process -Name 'DeadByDaylight*' -ErrorAction SilentlyContinue) {
        $running = $null
        if (-not [System.Threading.Mutex]::TryOpenExisting('Local\DbdClockOverlay', [ref]$running)) {
            Start-Process $ps -ArgumentList '-NoProfile', '-STA', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', "`"$overlay`"" -WindowStyle Hidden
            Start-Sleep -Seconds 15   # give it time to start before checking again
        } else { $running.Dispose() }
    }
    Start-Sleep -Seconds 5
}
