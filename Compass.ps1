# Compass (trial): which clock direction you're facing, worked out from your
# mouse. The overlay listens to raw mouse movement (the same Windows feature
# screen recorders use - it never touches the game) and adds it up. Two keys:
#   ScrollLock  calibrate: press, turn exactly one full circle to the right,
#            press again. Saved, so it's a one-off unless you change sensitivity.
#   F2       "I'm facing 12 right now" - sets north for this match. Press it
#            again whenever it has drifted (vaults, lockers, being carried and
#            hooked all turn the camera without the mouse).
#   F1       show / hide the strip.
# Dot-sourced by ClockOverlay.ps1 after the windows exist.

if (-not ('RawMouse' -as [type])) {
Add-Type -ReferencedAssemblies PresentationCore, WindowsBase, PresentationFramework -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Interop;
public static class RawMouse {
    [StructLayout(LayoutKind.Sequential)] public struct RAWINPUTDEVICE { public ushort usUsagePage; public ushort usUsage; public uint dwFlags; public IntPtr hwndTarget; }
    [StructLayout(LayoutKind.Sequential)] public struct RAWINPUTHEADER { public uint dwType; public uint dwSize; public IntPtr hDevice; public IntPtr wParam; }
    [StructLayout(LayoutKind.Explicit)] public struct RAWMOUSE {
        [FieldOffset(0)] public ushort usFlags; [FieldOffset(4)] public uint ulButtons; [FieldOffset(8)] public uint ulRawButtons;
        [FieldOffset(12)] public int lLastX; [FieldOffset(16)] public int lLastY; [FieldOffset(20)] public uint ulExtraInformation; }
    [DllImport("user32.dll", SetLastError = true)] static extern bool RegisterRawInputDevices(RAWINPUTDEVICE[] p, uint n, uint size);
    [DllImport("user32.dll")] static extern uint GetRawInputData(IntPtr hRawInput, uint cmd, IntPtr pData, ref uint pcbSize, uint cbSizeHeader);
    public static long TotalX = 0;   // sum of horizontal mouse movement (counts)
    public static long Events = 0;
    public static bool Enabled = true;   // only count while the game is the window in front
    // Chat wheel: while its mouse button is held the camera is frozen, so movement must not count.
    // Flags in RAWMOUSE.ulButtons: button 3 down/up 0x0010/0x0020, button 4 0x0040/0x0080, button 5 0x0100/0x0200.
    public static uint FreezeDownFlag = 0x0100, FreezeUpFlag = 0x0200;   // default: mouse button 5 (ThumbMouseButton2)
    public static bool FreezeHeld = false;
    public static bool Register(IntPtr hwnd) {
        var d = new RAWINPUTDEVICE[] { new RAWINPUTDEVICE { usUsagePage = 1, usUsage = 2, dwFlags = 0x100 /* INPUTSINK: also while not focused */, hwndTarget = hwnd } };
        return RegisterRawInputDevices(d, 1, (uint)Marshal.SizeOf(typeof(RAWINPUTDEVICE)));
    }
    public static IntPtr Hook(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled) {
        if (msg == 0x00FF) {   // WM_INPUT
            uint hs = (uint)Marshal.SizeOf(typeof(RAWINPUTHEADER)); uint size = 0;
            GetRawInputData(lParam, 0x10000003, IntPtr.Zero, ref size, hs);
            if (size > 0) {
                IntPtr buf = Marshal.AllocHGlobal((int)size);
                try {
                    if (GetRawInputData(lParam, 0x10000003, buf, ref size, hs) == size) {
                        var h = (RAWINPUTHEADER)Marshal.PtrToStructure(buf, typeof(RAWINPUTHEADER));
                        if (h.dwType == 0) {
                            var m = (RAWMOUSE)Marshal.PtrToStructure(new IntPtr(buf.ToInt64() + hs), typeof(RAWMOUSE));
                            uint bf = m.ulButtons & 0xFFFF;
                            if ((bf & FreezeDownFlag) != 0) FreezeHeld = true;
                            if ((bf & FreezeUpFlag) != 0) FreezeHeld = false;
                            if (Enabled && !FreezeHeld && (m.usFlags & 1) == 0) { TotalX += m.lLastX; Events++; }   // relative moves only
                        }
                    }
                } finally { Marshal.FreeHGlobal(buf); }
            }
        }
        return IntPtr.Zero;
    }
    public static HwndSourceHook GetHook() { return new HwndSourceHook(Hook); }
}
'@
}

$compass = @{ NorthCounts = $null; Calib = $null; LastText = ''; LastAngle = -1 }

# Turn rate from the game's own settings file: measured 3344 mouse counts per
# full turn at survivor mouse sensitivity 50, and the slider scales linearly,
# so counts per turn = 3344 * 50 / sensitivity. ScrollLock overrides this with a
# measured value; if the sensitivity later changes, the value is rescaled.
$script:gameIni = Join-Path $env:LOCALAPPDATA 'DeadByDaylight\Saved\Config\WindowsClient\GameUserSettings.ini'
function Get-GameSensitivity {
    try {
        $m = Select-String -Path $script:gameIni -Pattern '^SurvivorMouseSensitivity=(\d+)' -ErrorAction Stop | Select-Object -First 1
        if ($m) { [int]$m.Matches[0].Groups[1].Value }
    } catch { $null }
}
# Which mouse button opens the chat wheel (from the game's Input.ini), so the
# count pauses while it's held. Falls back to mouse button 5.
function Initialize-ChatWheelButton {
    $ini = Join-Path $env:LOCALAPPDATA 'DeadByDaylight\Saved\Config\WindowsClient\Input.ini'
    try {
        $m = Select-String -Path $ini -Pattern 'ActionName="QuickCommsWheelOpen".*Key=(\w+)' -ErrorAction Stop | Select-Object -First 1
        if ($m) {
            switch ($m.Matches[0].Groups[1].Value) {
                'MiddleMouseButton' { [RawMouse]::FreezeDownFlag = 0x0010; [RawMouse]::FreezeUpFlag = 0x0020 }
                'ThumbMouseButton'  { [RawMouse]::FreezeDownFlag = 0x0040; [RawMouse]::FreezeUpFlag = 0x0080 }
                'ThumbMouseButton2' { [RawMouse]::FreezeDownFlag = 0x0100; [RawMouse]::FreezeUpFlag = 0x0200 }
                default { }   # a keyboard key: nothing to pause on
            }
        }
    } catch {}
}
function Initialize-CompassRate {
    $sens = Get-GameSensitivity
    if (-not $sens) { return }
    if ($state.CountsPer360 -and $state.CalibSens) {
        if ($sens -ne $state.CalibSens) {
            $state.CountsPer360 = [long][Math]::Round($state.CountsPer360 * $state.CalibSens / $sens)
            $state.CalibSens = $sens; Save-Settings
        }
    } elseif (-not $state.CountsPer360) {
        $state.CountsPer360 = [long][Math]::Round(3344 * 50 / $sens); $state.CalibSens = $sens; Save-Settings
    } else { $state.CalibSens = $sens; Save-Settings }
}

# ---------- The bar (Skyrim-style, top middle) ----------
# A strip of clock numbers that slides as you turn; the marker in the middle
# points at the direction you're facing. 12 / 3 / 6 / 9 are big, the other
# hours small, a tick every 10 degrees.
$compassW = 560; $compassH = 44; $pxPerDeg = 4.0
$compassWindow = New-OverlayWindow 'DbD Clock Overlay compass'
$compassBorder = New-Object System.Windows.Controls.Border
$compassBorder.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(130, 8, 8, 12))
$compassBorder.CornerRadius = '6'
$compassBorder.Width = $compassW; $compassBorder.Height = $compassH
$compassCanvas = New-Object System.Windows.Controls.Canvas
$compassCanvas.Width = $compassW; $compassCanvas.Height = $compassH
$compassCanvas.ClipToBounds = $true
$compassBorder.Child = $compassCanvas
# fade the ends so numbers slide in and out softly
$compassBorder.OpacityMask = New-Object System.Windows.Media.LinearGradientBrush
$compassBorder.OpacityMask.StartPoint = '0,0'; $compassBorder.OpacityMask.EndPoint = '1,0'
foreach ($gs in @(@(0, 0), @(0.12, 1), @(0.88, 1), @(1, 0))) {
    $compassBorder.OpacityMask.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.Color]::FromArgb([byte](255 * $gs[1]), 0, 0, 0)), $gs[0]))
}
$tape = New-Object System.Windows.Controls.Canvas
$tapeTranslate = New-Object System.Windows.Media.TranslateTransform 0, 0
$tape.RenderTransform = $tapeTranslate
foreach ($k in -1, 0, 1) {
    for ($deg = 0; $deg -lt 360; $deg += 10) {
        $x = ($deg + $k * 360) * $pxPerDeg
        $major = ($deg % 90) -eq 0
        $hourMark = ($deg % 30) -eq 0
        $tick = New-Object System.Windows.Shapes.Line
        $tick.X1 = $x; $tick.X2 = $x
        $tick.Y1 = $(if ($hourMark) { 30 } else { 35 }); $tick.Y2 = $compassH - 3
        $tick.Stroke = [System.Windows.Media.Brushes]::White
        $tick.StrokeThickness = $(if ($major) { 2 } else { 1 })
        $tick.Opacity = $(if ($hourMark) { 0.9 } else { 0.5 })
        [void]$tape.Children.Add($tick)
        if ($hourMark) {
            $hour = [int]($deg / 30); if ($hour -eq 0) { $hour = 12 }
            $tb = New-Object System.Windows.Controls.TextBlock
            $tb.Text = "$hour"; $tb.Width = 44; $tb.TextAlignment = 'Center'
            $tb.FontSize = $(if ($major) { 19 } else { 13 }); $tb.FontWeight = $(if ($major) { 'Bold' } else { 'Normal' })
            $tb.Foreground = $(if ($major) { [System.Windows.Media.Brushes]::White } else { New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(210, 210, 210)) })
            [System.Windows.Controls.Canvas]::SetLeft($tb, $x - 22); [System.Windows.Controls.Canvas]::SetTop($tb, $(if ($major) { 4 } else { 10 }))
            [void]$tape.Children.Add($tb)
        }
    }
}
[void]$compassCanvas.Children.Add($tape)
# fixed centre marker
$marker = New-Object System.Windows.Shapes.Polygon
$marker.Points = [System.Windows.Media.PointCollection]::Parse("$($compassW / 2 - 7),1 $($compassW / 2 + 7),1 $($compassW / 2),10")
$marker.Fill = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(255, 80, 60))
[void]$compassCanvas.Children.Add($marker)
$markerLine = New-Object System.Windows.Shapes.Line
$markerLine.X1 = $compassW / 2; $markerLine.X2 = $compassW / 2; $markerLine.Y1 = 10; $markerLine.Y2 = $compassH
$markerLine.Stroke = $marker.Fill; $markerLine.StrokeThickness = 1.5; $markerLine.Opacity = 0.7
[void]$compassCanvas.Children.Add($markerLine)
# hint shown instead of the numbers until it's set up
$compassText = New-Object System.Windows.Controls.TextBlock
$compassText.FontSize = 15; $compassText.FontWeight = 'Bold'; $compassText.Foreground = [System.Windows.Media.Brushes]::White
$compassText.Width = $compassW; $compassText.TextAlignment = 'Center'
[System.Windows.Controls.Canvas]::SetTop($compassText, 11)
[void]$compassCanvas.Children.Add($compassText)
$compassWindow.Content = $compassBorder

# Start listening to the mouse (call once the status pill window is shown)
function Start-Compass {
    $h = (New-Object System.Windows.Interop.WindowInteropHelper $pillWindow).Handle
    $src = [System.Windows.Interop.HwndSource]::FromHwnd($h)
    $src.AddHook([RawMouse]::GetHook())
    if (-not [RawMouse]::Register($h)) { Add-Content (Join-Path $root 'overlay-errors.txt') ("{0:HH:mm:ss} compass: raw mouse registration failed" -f (Get-Date)) }
    Initialize-CompassRate
    Initialize-ChatWheelButton
    Update-CompassLayout
    # Slide the strip once per rendered frame (monitor refresh rate), not on a timer
    [System.Windows.Media.CompositionTarget]::add_Rendering([EventHandler]{ Update-Compass })
}

# Degrees clockwise from 12, or $null when not set up
function Get-CompassHeading {
    if (-not $state.CountsPer360 -or $null -eq $compass.NorthCounts) { return $null }
    $deg = (([RawMouse]::TotalX - $compass.NorthCounts) / [double]$state.CountsPer360 * 360.0) % 360.0
    if ($deg -lt 0) { $deg += 360 }
    $deg
}

# Called often (key timer); only touches the UI when something changed
function Update-Compass {
    if (-not $state.CompassOn) { return }
    $deg = Get-CompassHeading
    if ($null -eq $deg) {
        $text = if (-not $state.CountsPer360) { 'Compass: hold F2, one full turn right, hold F2' } else { 'Compass: F2 when facing 12' }
        $angle = 0; $tape.Opacity = 0.2
    } else {
        $text = ''; $angle = [Math]::Round($deg, 1); $tape.Opacity = 1
    }
    if ($text -ne $compass.LastText) { $compassText.Text = $text; $compass.LastText = $text }
    if ($angle -ne $compass.LastAngle) { $tapeTranslate.X = $compassW / 2 - $angle * $pxPerDeg; $compass.LastAngle = $angle }
}

# Top middle of the screen
function Update-CompassLayout {
    if (-not $state.CompassOn) { $compassWindow.Visibility = 'Hidden'; return }
    $compassWindow.Visibility = 'Visible'
    $compassWindow.UpdateLayout()
    $sw = [System.Windows.SystemParameters]::PrimaryScreenWidth
    $compassWindow.Left = ($sw - $compassWindow.ActualWidth) / 2
    # Endgame: drop below the collapse bar (it sits in the same strip)
    $compassWindow.Top = if ($collapse.Shown) { [System.Windows.SystemParameters]::PrimaryScreenHeight * 0.045 } else { 12 }
}

function Invoke-CompassKey([string]$which) {
    switch ($which) {
        'north' {
            # Drift log: how far the old heading was from the new "12", and how long since the last F2
            $old = Get-CompassHeading
            if ($null -ne $old) {
                $drift = $old; if ($drift -gt 180) { $drift -= 360 }
                $since = if ($compass.LastNorthAt) { [int]((Get-Date) - $compass.LastNorthAt).TotalSeconds } else { 0 }
                $log = Join-Path $root 'compass-log.txt'
                if ((Test-Path $log) -and (Get-Item $log).Length -gt 200KB) { Move-Item $log "$log.old" -Force }
                Add-Content $log ("{0:yyyy-MM-dd HH:mm:ss} drift {1,6:0.0} deg after {2,4} s  map={3}" -f (Get-Date), $drift, $since, $(if ($state.Map) { $state.Map.name } else { '-' }))
            }
            else {
                $log = Join-Path $root 'compass-log.txt'
                Add-Content $log ("{0:yyyy-MM-dd HH:mm:ss} set    (first F2 this match)  map={1}" -f (Get-Date), $(if ($state.Map) { $state.Map.name } else { '-' }))
            }
            $compass.LastNorthAt = Get-Date
            $compass.NorthCounts = [RawMouse]::TotalX
            if ($state.CountsPer360) { Show-Hint 'Compass: that way is 12' 3 } else { Show-Hint 'Compass: calibrate first - hold F2, one full turn right, ScrollLock' 6 }
        }
        'calibrate' {
            if ($null -eq $compass.Calib) {
                $compass.Calib = [RawMouse]::TotalX
                Show-Hint 'Compass: turn exactly ONE full circle to the RIGHT, then hold F2 again' 10
            } else {
                $n = [Math]::Abs([RawMouse]::TotalX - $compass.Calib)
                $compass.Calib = $null
                if ($n -lt 200) { Show-Hint 'Compass: that was too small a turn - hold F2 to try again' 5 }
                else { $state.CountsPer360 = [long]$n; $state.CalibSens = Get-GameSensitivity; Save-Settings; Show-Hint "Compass calibrated ($n per turn) - now F2 when facing 12" 6 }
            }
        }
        'toggle' { $state.CompassOn = -not $state.CompassOn; Save-Settings; Update-CompassLayout }
    }
    Update-Compass
}
