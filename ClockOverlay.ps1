# DbD Clock Callouts Overlay
# Shows the Hens333 clock-callout map (images by Lethia) for the map you are on,
# in a corner of the screen. Personal use only - the images are not ours to share.
#
# How it finds the map: every few seconds it takes a screenshot and reads the
# text on it with Windows' built-in OCR, looking for a map name (shown on the
# loading screen). It never touches the game's files or memory.
# Needs DbD in "Windowed Fullscreen" - true Fullscreen hides overlays.
#
# Holding TAB in a match (match details) makes it read the map name right away.
#
# Keys (work while the game is in front):
#   F6        pick the map by hand        PageDown  auto-detect on/off
#   F7        move to the next corner     F8       show / hide
#   F9        see-through level           F10      size
#   F4        you unhooked someone      Insert   you were unhooked    Delete  clear timers
#   F3        you used your exhaustion perk   PageUp  pick the perks you run
#   F5        chase timer start / stop    Home  move the timers up/down
#   End   timer size                 PrintScreen   screenshot with the overlay in it
#   (keys only work while DbD is the window in front; never F11 - it toggles DbD's fullscreen)
#   Pause   quit (or tray icon > Quit)

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

Add-Type -ReferencedAssemblies System.Windows.Forms @"
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class HotkeyWindow : NativeWindow, IDisposable {
    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr h, int id, uint mods, uint vk);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr h, int id);
    public event Action<int> Pressed;
    public HotkeyWindow() { CreateHandle(new CreateParams()); }
    // No MOD_NOREPEAT: if Windows misses a key-up (it can with the game in front),
    // NOREPEAT drops every later press. Repeats are filtered below instead.
    public bool Register(int id, uint mods, uint vk) { return RegisterHotKey(Handle, id, mods, vk); }
    private int lastId = -1; private int lastTick = 0;
    protected override void WndProc(ref Message m) {
        if (m.Msg == 0x0312 && Pressed != null) {
            int id = m.WParam.ToInt32(); int now = Environment.TickCount;
            // ignore auto-repeat from a held key (same key within 400 ms)
            if (id != lastId || now - lastTick > 400) Pressed(id);
            lastId = id; lastTick = now;
        }
        base.WndProc(ref m);
    }
    public void Dispose() { for (int i = 1; i <= 20; i++) UnregisterHotKey(Handle, i); DestroyHandle(); }
}
public static class OverlayNative {
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
    [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int i, int v);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern bool SetWindowDisplayAffinity(IntPtr h, uint affinity);
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
}
"@

$root = $PSScriptRoot

# Only one copy at a time (the auto-start watcher and a manual start can't double up)
$createdNew = $false
$instanceMutex = New-Object System.Threading.Mutex($true, 'Local\DbdClockOverlay', [ref]$createdNew)
if (-not $createdNew) { exit }
$settingsPath = Join-Path $root 'settings.json'
$maps = Get-Content (Join-Path $root 'maps.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$noMaps = -not (Get-ChildItem (Join-Path $root 'maps') -Filter *.png -ErrorAction SilentlyContinue)

$opacities = @(0.35, 0.55, 0.75, 1.0)
$heights   = @(260, 340, 440, 560)          # map height in screen units
$corners   = @('TopLeft', 'TopRight', 'BottomLeft', 'BottomRight', 'Left', 'Right')
$state = @{ Opacity = 2; Size = 1; Corner = 0; TimerPos = 0; TimerSize = 1; AutoDetect = $true; Visible = $true; Map = $null; Perks = @(); PerkTiers = [pscustomobject]@{}; AssumeLethal = $false; AutoPerks = $true; CountsPer360 = $null; CompassOn = $false; CalibSens = $null; TimersOn = $false }   # compass (trial) + timers (pre-10.2 perk values) start off; F1 / settings.json turn them on
if (Test-Path $settingsPath) {
    try {
        $saved = Get-Content $settingsPath -Raw | ConvertFrom-Json
        if ($saved.Opacity -ge 0 -and $saved.Opacity -lt $opacities.Count) { $state.Opacity = [int]$saved.Opacity }
        if ($saved.Size -ge 0 -and $saved.Size -lt $heights.Count)          { $state.Size = [int]$saved.Size }
        if ($saved.Corner -ge 0 -and $saved.Corner -lt $corners.Count)      { $state.Corner = [int]$saved.Corner }
        if ($saved.TimerPos -ge 0 -and $saved.TimerPos -le 2)              { $state.TimerPos = [int]$saved.TimerPos }
        if ($null -ne $saved.TimerSize -and $saved.TimerSize -ge 0 -and $saved.TimerSize -le 2) { $state.TimerSize = [int]$saved.TimerSize }
        if ($saved.Perks) { $state.Perks = @($saved.Perks | ForEach-Object { [string]$_ }) }
        if ($saved.PerkTiers) { $state.PerkTiers = $saved.PerkTiers }
        if ($null -ne $saved.AutoPerks) { $state.AutoPerks = [bool]$saved.AutoPerks }
        if ($null -ne $saved.AssumeLethal) { $state.AssumeLethal = [bool]$saved.AssumeLethal }
        if ($null -ne $saved.AutoDetect) { $state.AutoDetect = [bool]$saved.AutoDetect }
        if ($saved.CountsPer360 -gt 0) { $state.CountsPer360 = [long]$saved.CountsPer360 }
        if ($null -ne $saved.CompassOn) { $state.CompassOn = [bool]$saved.CompassOn }
        # Perk / unhook / exhaustion / chase timers (the collapse countdown is separate)
        if ($null -ne $saved.TimersOn) { $state.TimersOn = [bool]$saved.TimersOn }
        if ($saved.CalibSens -gt 0) { $state.CalibSens = [int]$saved.CalibSens }
    } catch {}
}
function Save-Settings {
    @{ Opacity = $state.Opacity; Size = $state.Size; Corner = $state.Corner; TimerPos = $state.TimerPos; TimerSize = $state.TimerSize; AutoDetect = $state.AutoDetect; Perks = @($state.Perks); PerkTiers = $state.PerkTiers; AssumeLethal = $state.AssumeLethal; AutoPerks = $state.AutoPerks; CountsPer360 = $state.CountsPer360; CompassOn = $state.CompassOn; CalibSens = $state.CalibSens; TimersOn = $state.TimersOn } |
        ConvertTo-Json | Set-Content $settingsPath -Encoding utf8
}

# ---------- Overlay windows: the map (moves with F7) and the status pill (always top right) ----------
function New-OverlayWindow([string]$title) {
    $w = New-Object System.Windows.Window
    $w.WindowStyle = 'None'
    $w.AllowsTransparency = $true
    $w.Background = [System.Windows.Media.Brushes]::Transparent
    $w.Topmost = $true
    $w.ShowInTaskbar = $false
    $w.ShowActivated = $false
    $w.SizeToContent = 'WidthAndHeight'
    $w.Title = $title
    $w.Add_SourceInitialized({
        param($s, $e)
        $h = (New-Object System.Windows.Interop.WindowInteropHelper $s).Handle
        $ex = [OverlayNative]::GetWindowLong($h, -20)
        # Click-through, no taskbar/alt-tab entry, never takes focus
        [void][OverlayNative]::SetWindowLong($h, -20, ($ex -bor 0x20 -bor 0x80000 -bor 0x80 -bor 0x08000000))
        # Keep it out of screenshots, so OCR never reads our own text
        [void][OverlayNative]::SetWindowDisplayAffinity($h, 0x11)
    })
    $w
}
$window = New-OverlayWindow 'DbD Clock Overlay'
$pillWindow = New-OverlayWindow 'DbD Clock Overlay status'
. (Join-Path $root 'Timers.ps1')
. (Join-Path $root 'Compass.ps1')
. (Join-Path $root 'Roulette.ps1')

$image = New-Object System.Windows.Controls.Image
$image.Stretch = 'Uniform'
[System.Windows.Media.RenderOptions]::SetBitmapScalingMode($image, 'HighQuality')
# Small status pill, always on screen, so you can see it is running
$status = New-Object System.Windows.Controls.Border
$status.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(190, 20, 20, 30))
$status.CornerRadius = 9
$status.Padding = '8,3,10,3'
$statusRow = New-Object System.Windows.Controls.StackPanel
$statusRow.Orientation = 'Horizontal'
$statusDot = New-Object System.Windows.Shapes.Ellipse
$statusDot.Width = 9; $statusDot.Height = 9
$statusDot.Margin = '0,0,7,0'
$statusDot.VerticalAlignment = 'Center'
$statusText = New-Object System.Windows.Controls.TextBlock
$statusText.Foreground = [System.Windows.Media.Brushes]::White
$statusText.FontFamily = 'Segoe UI'
$statusText.FontSize = 13
[void]$statusRow.Children.Add($statusDot)
[void]$statusRow.Children.Add($statusText)
$status.Child = $statusRow
$pillWindow.Content = $status
# Killer cheat card: shown for a few seconds when the Esc screen names the killer
$killerWindow = New-OverlayWindow 'DbD Clock Overlay killer'
$killerCard = New-Object System.Windows.Controls.Border
$killerCard.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(200, 20, 20, 30))
$killerCard.CornerRadius = 9
$killerCard.Padding = '12,8,12,9'
$killerPanel = New-Object System.Windows.Controls.StackPanel
$killerCard.Child = $killerPanel
$killerWindow.Content = $killerCard
$killers = @()
try { $killers = @((Get-Content (Join-Path $root 'killers.json') -Raw -Encoding UTF8 | ConvertFrom-Json) | ForEach-Object { $_ }) } catch {}
$killerShown = @(); $killerUntil = $null

# Endgame Collapse countdown: sits just right of the game's collapse bar (top of
# the screen). The detector reports how full the bar is every scan; between
# scans the number counts down by itself. A full bar = 120 s at normal speed;
# it drains at half speed while someone is dying / hooked / caged (max 240 s).
$collapseWindow = New-OverlayWindow 'DbD Clock Overlay collapse'
$collapseCard = New-Object System.Windows.Controls.Border
$collapseCard.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(170, 20, 20, 30))
$collapseCard.CornerRadius = 7
$collapseCard.Padding = '8,1,8,2'
$collapseText = New-Object System.Windows.Controls.TextBlock
$collapseText.FontFamily = 'Segoe UI'; $collapseText.FontSize = 17; $collapseText.FontWeight = 'Bold'
$collapseText.Foreground = [System.Windows.Media.Brushes]::White
$collapseCard.Child = $collapseText
$collapseWindow.Content = $collapseCard
$collapse = @{ Reads = New-Object System.Collections.ArrayList; LastSeq = 0; Shown = $false }
$collapseNormal = 1.0 / 120   # bar fraction drained per second at normal speed

function Update-Collapse {
    if ($sync.CollapseSeq -ne $collapse.LastSeq) {
        $collapse.LastSeq = $sync.CollapseSeq
        $f = [double]$sync.CollapseFrac
        $last = if ($collapse.Reads.Count) { $collapse.Reads[$collapse.Reads.Count - 1] } else { $null }
        if ($last -and $f -gt $last.F + 0.03) { $collapse.Reads.Clear() }   # a fuller bar = a new endgame
        [void]$collapse.Reads.Add(@{ T = $sync.CollapseAt; F = $f })
        while ($collapse.Reads.Count -gt 2 -and ($sync.CollapseAt - $collapse.Reads[0].T).TotalSeconds -gt 12) { $collapse.Reads.RemoveAt(0) }
    }
    $reads = $collapse.Reads
    # Other things at the top of the screen were once mistaken for the bar (19 Oct).
    # So: show it once all gens are done (gate switch prompt seen), or when the
    # "bar" has really been draining like the collapse does (half or full speed).
    $real = $sync.GatesPowered
    if (-not $real -and $reads.Count -ge 2) {
        $r0 = $reads[0]; $rN = $reads[$reads.Count - 1]; $sp = ($rN.T - $r0.T).TotalSeconds
        if ($sp -ge 6) { $rate = ($r0.F - $rN.F) / $sp; $real = $rate -ge 0.35 * $collapseNormal -and $rate -le 1.4 * $collapseNormal }
    }
    $show = $real -and $reads.Count -ge 2 -and $sync.MenuStreak -lt 2 -and ((Get-Date) - $reads[$reads.Count - 1].T).TotalSeconds -lt 8
    if (-not $show) {
        if ($collapse.Shown) { $collapse.Shown = $false; $collapseWindow.Hide(); Update-CompassLayout }
        if ($reads.Count -and ((Get-Date) - $reads[$reads.Count - 1].T).TotalSeconds -ge 8) { $reads.Clear() }
        return
    }
    # Speed from the last few readings (at least 4 s apart); assume normal until then
    $b = $reads[$reads.Count - 1]
    $a = $reads[0]   # newest reading that is still at least 4 s older than the last one
    foreach ($q in $reads) { if (($b.T - $q.T).TotalSeconds -ge 4) { $a = $q } }
    $span = ($b.T - $a.T).TotalSeconds
    $slowed = $span -ge 4 -and (($a.F - $b.F) / $span) -lt 0.75 * $collapseNormal
    $speed = if ($slowed) { $collapseNormal / 2 } else { $collapseNormal }
    $now = [Math]::Max(0.0, $b.F -$speed * ((Get-Date) - $b.T).TotalSeconds)
    $secs = [int][Math]::Ceiling($now / $speed)
    $collapseText.Text = ('Collapse {0}:{1:00}' -f [int][Math]::Floor($secs / 60), ($secs % 60)) + $(if ($slowed) { '  slowed' } else { '' })
    $collapseText.Foreground = if ($sync.CollapseOrange) { [System.Windows.Media.Brushes]::Orange } else { [System.Windows.Media.Brushes]::White }
    if (-not $collapse.Shown) {
        $collapse.Shown = $true
        $collapseWindow.Show(); $collapseWindow.UpdateLayout()
        $sw = [System.Windows.SystemParameters]::PrimaryScreenWidth; $sh = [System.Windows.SystemParameters]::PrimaryScreenHeight
        $collapseWindow.Left = $sw * 0.812
        $collapseWindow.Top = [Math]::Max(0, $sh * 0.0361 - $collapseWindow.ActualHeight / 2)
        Update-CompassLayout   # the compass moves down so it doesn't cover the bar
    }
}

$killerCardOn = $false   # shelved for now (see the UI tick); the DBD_OVERLAY_KILLER test hook still works
function Show-KillerCard([string]$title) {
    $k = $killers | Where-Object { $_.title -eq $title } | Select-Object -First 1
    if (-not $k) { return $false }
    $killerPanel.Children.Clear()
    $head = New-Object System.Windows.Controls.TextBlock
    $head.Text = [Globalization.CultureInfo]::InvariantCulture.TextInfo.ToTitleCase($k.title.ToLowerInvariant())
    $head.FontFamily = 'Segoe UI'; $head.FontSize = 15; $head.FontWeight = 'Bold'
    $head.Foreground = [System.Windows.Media.Brushes]::White
    $head.Margin = '0,0,0,3'
    [void]$killerPanel.Children.Add($head)
    foreach ($l in $k.lines) {
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = $l; $tb.FontFamily = 'Segoe UI'; $tb.FontSize = 13
        $tb.Foreground = [System.Windows.Media.Brushes]::White
        [void]$killerPanel.Children.Add($tb)
    }
    $killerWindow.Show()
    # Under the status pill, top right - or left of the map if the map is up there
    $killerWindow.UpdateLayout(); $pillWindow.UpdateLayout()
    $sw = [System.Windows.SystemParameters]::PrimaryScreenWidth
    $x = $sw - $killerWindow.ActualWidth - 16
    if ($state.Map -and $state.Visible -and $corners[$state.Corner] -eq 'TopRight') { $x = $window.Left - $killerWindow.ActualWidth - 10 }
    $killerWindow.Left = $x; $killerWindow.Top = $pillWindow.Top + $pillWindow.ActualHeight + 8
    $script:killerUntil = (Get-Date).AddSeconds(8)
    $true
}
# Map + extra landmark labels (landmarks.json) drawn on top of the image
$labelCanvas = New-Object System.Windows.Controls.Canvas
$labelCanvas.IsHitTestVisible = $false
$mapGrid = New-Object System.Windows.Controls.Grid
[void]$mapGrid.Children.Add($image)
[void]$mapGrid.Children.Add($labelCanvas)
$window.Content = $mapGrid
$landmarks = $null
try { $landmarks = Get-Content (Join-Path $root 'landmarks.json') -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
$crops = $null; $mapCrop = $null
try { $crops = Get-Content (Join-Path $root 'crops.json') -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}

function Update-MapLabels {
    $labelCanvas.Children.Clear()
    if (-not $state.Map -or -not $landmarks) { return }
    $list = $landmarks.($state.Map.name)
    if (-not $list) { return }
    $window.UpdateLayout()
    $w = $image.ActualWidth; $h = $image.ActualHeight
    if ($w -le 0 -or $h -le 0) { return }
    $labelCanvas.Width = $w; $labelCanvas.Height = $h
    $labelCanvas.Opacity = [Math]::Min(1.0, $opacities[$state.Opacity] + 0.15)
    $size = [Math]::Max(9, [Math]::Min($w, $h) * 0.032)
    # label positions are fractions of the whole picture; the shown map may be trimmed
    $cx = 0.0; $cy = 0.0; $cw = 1.0; $ch = 1.0
    if ($script:mapCrop) { $cx = $script:mapCrop[0]; $cy = $script:mapCrop[1]; $cw = $script:mapCrop[2]; $ch = $script:mapCrop[3] }
    foreach ($l in $list) {
        $lx = ($l.x - $cx) / $cw; $ly = ($l.y - $cy) / $ch
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = $l.t; $tb.FontSize = $size; $tb.FontWeight = 'SemiBold'
        $tb.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(255, 225, 120))
        $tb.Effect = New-Object System.Windows.Media.Effects.DropShadowEffect
        $tb.Effect.BlurRadius = 3; $tb.Effect.ShadowDepth = 1; $tb.Effect.Opacity = 1
        $tb.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
        # kept inside the frame (edge labels could fall off a trimmed map)
        $tl = [Math]::Min([Math]::Max(0.0, $lx * $w - $tb.DesiredSize.Width / 2), [Math]::Max(0.0, $w - $tb.DesiredSize.Width))
        $tt = [Math]::Min([Math]::Max(0.0, $ly * $h - $tb.DesiredSize.Height / 2), [Math]::Max(0.0, $h - $tb.DesiredSize.Height))
        [System.Windows.Controls.Canvas]::SetLeft($tb, $tl)
        [System.Windows.Controls.Canvas]::SetTop($tb, $tt)
        [void]$labelCanvas.Children.Add($tb)
    }
}

$dotColors = @{
    Green = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(70, 210, 110))
    Amber = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(240, 180, 50))
    Red   = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(235, 70, 70))
}

# A short message replaces the normal status text for a few seconds
function Show-Hint([string]$text, [int]$seconds = 4) {
    $script:hintText = $text
    $script:hintUntil = (Get-Date).AddSeconds($seconds)
    Update-Status
}

function Update-Status {
    $scanAge = if ($sync.LastScan) { ((Get-Date) - $sync.LastScan).TotalSeconds } else { 0 }
    if ($noMaps)                              { $color = 'Red';   $text = 'Clock overlay - no maps yet: run "1 - Download maps" first' }
    elseif (-not $state.AutoDetect)           { $color = 'Amber'; $text = 'Clock overlay - auto-detect off (F6 pick map)' }
    elseif ($sync.Error -or $scanAge -gt 15)  { $color = 'Red';   $text = 'Clock overlay - detection stopped' }
    elseif ($state.Map)                       { $color = 'Green'; $text = $state.Map.name }
    elseif ($sync.LastHud -and ((Get-Date) - $sync.LastHud).TotalSeconds -lt 90) {
        # In-match prompts seen recently, but no map name yet
        $color = 'Amber'; $text = 'Map not detected - hold TAB'
    }
    elseif (-not $sync.DbdVisible)           { $color = 'Green'; $text = 'Clock overlay - waiting for Dead by Daylight' }
    else                                      { $color = 'Green'; $text = 'Clock overlay - watching for map' }
    if ($state.Map -and -not $state.Visible)  { $text += '  (hidden, F8)' }
    if ($script:hintUntil) {
        if ((Get-Date) -lt $script:hintUntil) { $text = $script:hintText } else { $script:hintUntil = $null }
    }
    $statusDot.Fill = $dotColors[$color]
    if ($statusText.Text -ne $text) { $statusText.Text = $text; Update-Layout }
}

function Update-Layout {
    $image.Opacity = $opacities[$state.Opacity]
    $image.Height = $heights[$state.Size]
    $image.Visibility = if ($state.Map -and $state.Visible) { 'Visible' } else { 'Collapsed' }
    $labelCanvas.Visibility = $image.Visibility
    Update-MapLabels
    $sw = [System.Windows.SystemParameters]::PrimaryScreenWidth
    $sh = [System.Windows.SystemParameters]::PrimaryScreenHeight
    $pillWindow.UpdateLayout()
    $pillWindow.Left = $sw - $pillWindow.ActualWidth - 16; $pillWindow.Top = 16
    $window.UpdateLayout()
    $w = $window.ActualWidth; $h = $window.ActualHeight; $m = 16
    switch ($corners[$state.Corner]) {
        'TopLeft'     { $x = $m;           $y = $m }
        'TopRight'    { $x = $sw - $w - $m; $y = $m }
        'BottomLeft'  { $x = $m;           $y = $sh - $h - $m }
        'BottomRight' { $x = $sw - $w - $m; $y = $sh - $h - $m }
        'Left'        { $x = $m;           $y = ($sh - $h) / 2 }
        'Right'       { $x = $sw - $w - $m; $y = ($sh - $h) / 2 }
    }
    $window.Left = $x; $window.Top = $y
    Update-CompassLayout
}

function Set-Map($map) {
    $newMatch = -not $state.Map
    $state.Map = $map
    $bi = New-Object System.Windows.Media.Imaging.BitmapImage
    $bi.BeginInit()
    $bi.UriSource = New-Object System.Uri (Join-Path $root "maps\$($map.file)")
    $bi.CacheOption = 'OnLoad'
    $bi.DecodePixelHeight = 900
    $bi.EndInit()
    # Trim the dark patterned background around the map (crops.json, made by
    # make-crops.ps1) so the map itself sits in the screen corner
    $script:mapCrop = $null
    $cr = if ($crops) { $crops.($map.file) } else { $null }
    if ($cr) {
        $rect = New-Object System.Windows.Int32Rect ([int]($cr[0] * $bi.PixelWidth)), ([int]($cr[1] * $bi.PixelHeight)), ([int]($cr[2] * $bi.PixelWidth)), ([int]($cr[3] * $bi.PixelHeight))
        if ($rect.X + $rect.Width -gt $bi.PixelWidth) { $rect.Width = $bi.PixelWidth - $rect.X }
        if ($rect.Y + $rect.Height -gt $bi.PixelHeight) { $rect.Height = $bi.PixelHeight - $rect.Y }
        $image.Source = New-Object System.Windows.Media.Imaging.CroppedBitmap $bi, $rect
        $script:mapCrop = $cr
    } else { $image.Source = $bi }
    $state.Visible = $true
    Update-Layout
    Update-Status
    $tray.Text = "DbD Clock Overlay - $($map.name)"
    if ($newMatch -and $state.AssumeLethal) { [void](Start-EventTimers 'match_start') }
    if ($newMatch) { $compass.NorthCounts = $null; Update-Compass }   # new map: north unknown until F2
}

# ---------- Map picker (F6) ----------
function Show-Picker {
    if ($script:picker) { $script:picker.Activate(); return }
    $sync.Paused = $true
    $p = New-Object System.Windows.Window
    $p.Title = 'Pick a map'
    $p.Width = 380; $p.Height = 520
    $p.WindowStartupLocation = 'CenterScreen'
    $p.Topmost = $true
    $p.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(30, 30, 40))
    $dock = New-Object System.Windows.Controls.DockPanel
    $dock.Margin = 10
    $box = New-Object System.Windows.Controls.TextBox
    $box.FontSize = 16; $box.Margin = '0,0,0,8'; $box.Padding = 4
    [System.Windows.Controls.DockPanel]::SetDock($box, 'Top')
    $list = New-Object System.Windows.Controls.ListBox
    $list.FontSize = 15
    $list.Background = $p.Background
    $list.Foreground = [System.Windows.Media.Brushes]::White
    $list.DisplayMemberPath = 'label'
    [void]$dock.Children.Add($box); [void]$dock.Children.Add($list)
    $p.Content = $dock
    $all = $maps | ForEach-Object { [pscustomobject]@{ label = "$($_.name)   ($($_.realm))"; map = $_ } }
    $fill = {
        $q = $box.Text.Trim()
        $list.ItemsSource = @($all | Where-Object { -not $q -or $_.label -like "*$q*" })
        if ($list.Items.Count) { $list.SelectedIndex = 0 }
    }
    & $fill
    $choose = { if ($list.SelectedItem) { Set-Map $list.SelectedItem.map; $p.Close() } }
    $box.Add_TextChanged($fill)
    $box.Add_PreviewKeyDown({
        param($s, $e)
        switch ($e.Key) {
            'Enter'  { & $choose; $e.Handled = $true }
            'Escape' { $p.Close(); $e.Handled = $true }
            'Down'   { if ($list.SelectedIndex -lt $list.Items.Count - 1) { $list.SelectedIndex++ }; $list.ScrollIntoView($list.SelectedItem); $e.Handled = $true }
            'Up'     { if ($list.SelectedIndex -gt 0) { $list.SelectedIndex-- }; $list.ScrollIntoView($list.SelectedItem); $e.Handled = $true }
        }
    })
    $list.Add_MouseDoubleClick($choose)
    $p.Add_Closed({ $script:picker = $null; $sync.Paused = $false })
    $script:picker = $p
    $p.Show(); $p.Activate(); [void]$box.Focus()
}

# ---------- Background map detection ----------
$sync = [hashtable]::Synchronized(@{ Enabled = $state.AutoDetect; Paused = $false; Quit = $false; Blackout = $null; Detected = $null; Seq = 0; MenuStreak = 0; ScanNow = $false; HaveMap = $false; RescueSeq = 0; UnhookedSeq = 0; UnhookedSource = @(); CarriedSeq = 0; DeadSeq = 0; EscMenu = $false; EffectSeq = 0; EffectText = ''; ChaseEndSeq = 0; AutoPerks = $state.AutoPerks; PerkSeq = 0; DetectedPerks = @(); PerkScores = @(); LobbyScanned = $false; KillerSeq = 0; KillerTitle = ''; CollapseSeq = 0; CollapseFrac = 0.0; CollapseOrange = $false; CollapseAt = $null; LobbyAt = $null; LoadoutNow = $false; LoadoutAt = $null })
$runspace = [runspacefactory]::CreateRunspace()
$runspace.ApartmentState = 'MTA'
$runspace.Open()
$runspace.SessionStateProxy.SetVariable('sync', $sync)
$runspace.SessionStateProxy.SetVariable('root', $root)
$runspace.SessionStateProxy.SetVariable('maps', $maps)
$runspace.SessionStateProxy.SetVariable('logPath', (Join-Path $root 'ocr-log.txt'))
$detector = [powershell]::Create()
$detector.Runspace = $runspace
[void]$detector.AddScript({
    . (Join-Path $root 'OcrLib.ps1')
    . (Join-Path $root 'PerkMatch.ps1')
    $perkJson = Get-Content (Join-Path $root 'perks.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $perkList = $perkJson.perks
    $timerPerkNames = @($perkJson.timers | ForEach-Object { $_.perk } | Select-Object -Unique)
    # Killer titles for the cheat card (accents are dropped, so ONRYO with a macron still matches)
    $killerKeys = @()
    try { $killerKeys = @((Get-Content (Join-Path $root 'killers.json') -Raw -Encoding UTF8 | ConvertFrom-Json) | ForEach-Object { @{ Title = $_.title; Key = ' ' + (ConvertTo-MatchKey $_.title) + ' ' } }) } catch {}
    $lastKiller = $null
    $prevEffects = @()
    $iconDir = Join-Path $root 'icons'
    # Where your 4 perk diamonds sit in the lobby (next to your character, top
    # right), as fractions of the screen so other resolutions work. Measured on
    # a 3840x2160 screen; the diamond half-diagonal is 55 px there.
    $perkSlots = @(@{X=0.9049; Y=0.1597}, @{X=0.8880; Y=0.1898}, @{X=0.9219; Y=0.1898}, @{X=0.9049; Y=0.2199})
    $perkHalfFrac = 55 / 2160
    $lastFlat = ''; $tabScan = $false
    # Match start: for a while after the loading screen / lobby, scan fast and
    # also read the bottom-left corner zoomed in (the map name there is small).
    # Put a file called save-start-frames.flag next to this script to also save
    # those first frames to Screenshots\start (for tuning the detection).
    $darkSeen = [datetime]::MinValue; $startFrames = 0; $burst = $false; $lastFrameSave = [datetime]::MinValue
    $saveStart = Test-Path (Join-Path $root 'save-start-frames.flag')
    $startDir = Join-Path $root 'Screenshots\start'
    # Endgame frames (to locate the Endgame Collapse bar): with save-endgame-frames.flag
    # present, once the gate switch prompt ("OPEN ESCAPE") shows, save the top strip of
    # the screen every 4 s for up to 4 min. Local only.
    $saveEnd = Test-Path (Join-Path $root 'save-endgame-frames.flag')
    $endDir = Join-Path $root 'Screenshots\endgame'
    $gatesSeen = [datetime]::MinValue; $lastEndSave = [datetime]::MinValue; $endFrames = 0
    $scanLog = Join-Path $root 'scan-log.txt'
    while (-not $sync.Quit) {
        $burst = $false; $brightness = -1; $textLen = -1; $menuHits = @()
        # Test hook: DBD_OVERLAY_TESTSHOT=<png> reads that file instead of the screen
        $testShot = $env:DBD_OVERLAY_TESTSHOT
        $sync.DbdInFront = if ($testShot) { $true } else { Test-DbdInFront }
        # Game in front: read the screen. Game running behind another window (you
        # tabbed to a second monitor while a match loads): read the game window
        # alone, so the intro with the map name isn't missed.
        $sync.DbdVisible = $sync.DbdInFront -or ((Get-DbdWindow) -ne [IntPtr]::Zero)
        if ($sync.Enabled -and -not $sync.Paused -and $sync.DbdVisible) {
            try {
                $r = $sync.Blackout
                $rect = if ($r) { New-Object System.Drawing.Rectangle $r[0], $r[1], $r[2], $r[3] } else { [System.Drawing.Rectangle]::Empty }
                $bmp = if ($testShot) { [System.Drawing.Bitmap]::FromFile($testShot) } elseif ($sync.DbdInFront) { Get-ScreenBitmap $rect } else { Get-DbdWindowBitmap $rect }
                if (-not $bmp) { throw 'game window capture not available' }
                $text = Read-BitmapText $bmp
                $textLen = $text.Length
                $menuHits = Get-MenuWordHits $text
                $isLoading = $text -match 'BY DAYLIGHT'
                # Lobby (for the perk roulette button): ready button / party / chat box
                # on screen, and none of the end-of-match words
                if (@($menuHits | Where-Object { $_ -in 'READY', 'LEAVE PARTY', 'ENTER TEXT' }).Count -and
                    -not @($menuHits | Where-Object { $_ -in 'MATCH RESULT', 'BLOODPOINTS EARNED', 'SPECTATE', 'SCOREBOARD', 'CONTINUE' }).Count) { $sync.LobbyAt = Get-Date }
                # loadout panel on screen right now (the perk roulette only shows then)
                # (a full-screen read now and then misses the word - the quick title
                # check gets the last say, so the button doesn't blink off mid-spin)
                $sync.LoadoutNow = ($menuHits -contains 'LOADOUT') -or ($sync.DbdInFront -and -not $testShot -and $menuHits.Count -and (Test-LoadoutTitle))
                if ($sync.LoadoutNow) { $sync.LoadoutAt = Get-Date }
                if ($text -match 'OPEN ESCAPE') { $sync.GatesPowered = $true }      # gate switch prompt = all gens done
                # Endgame Collapse bar: how full it is (pixels only, a few ms)
                $cb = Get-CollapseBar $bmp
                if ($cb) { $sync.CollapseFrac = $cb.Frac; $sync.CollapseOrange = $cb.Orange; $sync.CollapseAt = Get-Date; $sync.CollapseSeq++ }
                if ($saveEnd) {
                    if ($text -match 'OPEN ESCAPE') { if (((Get-Date) - $gatesSeen).TotalMinutes -gt 6) { $endFrames = 0 }; $gatesSeen = Get-Date }
                    if ($text -match 'MATCH RESULT|SCOREBOARD') { $gatesSeen = [datetime]::MinValue }
                    if (((Get-Date) - $gatesSeen).TotalSeconds -lt 240 -and $endFrames -lt 70 -and ((Get-Date) - $lastEndSave).TotalSeconds -ge 4) {
                        New-Item -ItemType Directory -Force $endDir | Out-Null
                        $eh = [int]($bmp.Height * 0.22)
                        $strip = $bmp.Clone((New-Object System.Drawing.Rectangle 0, 0, $bmp.Width, $eh), $bmp.PixelFormat)
                        $strip.Save((Join-Path $endDir ('{0:MMdd-HHmmss}.png' -f (Get-Date))), [System.Drawing.Imaging.ImageFormat]::Png)
                        $strip.Dispose(); $endFrames++; $lastEndSave = Get-Date
                    }
                }
                # Average brightness: the loading screen is (nearly) black, and the
                # match intro follows it - that's when the map name is on screen
                $tiny = New-Object System.Drawing.Bitmap 16, 9
                $tg = [System.Drawing.Graphics]::FromImage($tiny)
                $tg.InterpolationMode = 'HighQualityBilinear'
                $tg.DrawImage($bmp, 0, 0, 16, 9); $tg.Dispose()
                $sum = 0
                for ($ty = 0; $ty -lt 9; $ty++) { for ($tx = 0; $tx -lt 16; $tx++) { $c = $tiny.GetPixel($tx, $ty); $sum += $c.R + $c.G + $c.B } }
                $tiny.Dispose()
                $brightness = $sum / (144 * 3 * 255)
                if ($brightness -lt 0.08 -or $isLoading) { $darkSeen = Get-Date; $startFrames = 0 }
                $burst = (-not $sync.HaveMap) -and (-not $isLoading) -and ($brightness -ge 0.08) -and ($menuHits.Count -eq 0) -and (((Get-Date) - $darkSeen).TotalSeconds -lt 45)
                if ($burst) {
                    $cw = [int]($bmp.Width * 0.5); $ch = [int]($bmp.Height * 0.45)
                    $crop = New-Object System.Drawing.Bitmap ($cw * 2), ($ch * 2)
                    $cg = [System.Drawing.Graphics]::FromImage($crop)
                    $cg.InterpolationMode = 'HighQualityBicubic'
                    $cg.DrawImage($bmp, (New-Object System.Drawing.Rectangle 0, 0, ($cw * 2), ($ch * 2)), (New-Object System.Drawing.Rectangle 0, ($bmp.Height - $ch), $cw, $ch), [System.Drawing.GraphicsUnit]::Pixel)
                    $cg.Dispose()
                    $cropText = Read-BitmapText $crop
                    $crop.Dispose()
                    if ($cropText) { $text = $text + "`n" + $cropText }
                    if ($saveStart -and $startFrames -lt 40 -and ((Get-Date) - $lastFrameSave).TotalMilliseconds -ge 1000) {
                        New-Item -ItemType Directory -Force $startDir | Out-Null
                        $bmp.Save((Join-Path $startDir ('{0:HH-mm-ss}.jpg' -f (Get-Date))), [System.Drawing.Imaging.ImageFormat]::Jpeg)
                        $startFrames++; $lastFrameSave = Get-Date
                    }
                }
                # In the lobby (READY button showing): read the 4 perk diamonds once
                if ($sync.AutoPerks -and -not $sync.LobbyScanned -and ($menuHits -contains 'READY')) {
                    try {
                        $sh = $bmp.Height; $swd = $bmp.Width
                        $centers = $perkSlots | ForEach-Object { @{ X = [int]($_.X * $swd); Y = [int]($_.Y * $sh) } }
                        $found = Find-PerksInBitmap $bmp $centers $iconDir $perkList ([int]($perkHalfFrac * $sh))
                        # keep a slot only when it's a clear match
                        $names = @($found | Where-Object { $_.Name -and $_.Score -ge 0.62 -and ($_.Score - $_.SecondScore) -ge 0.03 } | ForEach-Object { $_.Name })
                        $sync.PerkScores = @($found | ForEach-Object { "$($_.Name) $($_.Score)" })
                        if ($names.Count -ge 2) { $sync.DetectedPerks = $names; $sync.PerkSeq++ }
                        $sync.LobbyScanned = $true
                    } catch { $sync.PerkError = "perk scan: $($_.Exception.Message)" }
                }
                $bmp.Dispose()
                if ($menuHits.Count -ge 2) {
                    # Lobby / menus / end screen: the match is over. Don't read map
                    # names here (offerings and the scoreboard can mention them)
                    $sync.MenuStreak++
                    $sync.LastHud = $null   # out of the trial - stop any "not detected" warning
                    $sync.GatesPowered = $false
                    $prevEffects = @()
                    $lastKiller = $null
                    $hit = $null
                } else {
                    $sync.MenuStreak = 0
                    $hit = Find-MapInText $text $maps
                    if ($hit) { $sync.Detected = $hit.name; $sync.DetectedViaTab = $tabScan; $sync.Seq++ }
                    if ((Get-HudWordHits $text).Count -gt 0) { $sync.LastHud = Get-Date; $sync.LobbyScanned = $false }
                    $ev = Get-ScoreEvents $text
                    if ($ev.Rescue)   { $sync.RescueSeq++ }
                    if ($ev.Unhooked) { $sync.UnhookedSeq++ }
                    if ($ev.Carried)  { $sync.CarriedSeq++ }
                    if ($ev.Dead)     { $sync.DeadSeq++ }
                    $sync.EscMenu = [bool]$ev.MenuOpen
                    # Killer cheat card: the in-match Esc / PLAYERS screen names the killer.
                    # Only read it there - the store and menus mention killer titles too.
                    if ($ev.MenuOpen -and $killerKeys.Count) {
                        $kk = ' ' + (ConvertTo-MatchKey ($text -replace "`n", ' ')) + ' '
                        $kh = $killerKeys | Where-Object { $kk.Contains($_.Key) } | Select-Object -First 1
                        if ($kh -and $kh.Title -ne $lastKiller) { $lastKiller = $kh.Title; $sync.KillerTitle = $kh.Title; $sync.KillerSeq++ }
                    }
                    if ($ev.Unhooked) {
                        # which perks the screen names at that moment (the rescuer's Borrowed Time etc.)
                        $k2 = ' ' + (ConvertTo-MatchKey ($text -replace "`n", ' ')) + ' '
                        $sync.UnhookedSource = @($timerPerkNames | Where-Object { $k2.Contains(' ' + (ConvertTo-MatchKey $_) + ' ') })
                    }
                    # Status effects that just appeared, with their cause
                    $fx = @(Get-StatusEffects $text)
                    $fxNames = @($fx | ForEach-Object { $_.Effect })
                    $newFx = @($fx | Where-Object { $prevEffects -notcontains $_.Effect })
                    $prevEffects = $fxNames
                    if ($newFx.Count) {
                        $sync.EffectText = ($newFx | ForEach-Object { if ($_.Cause) { "$($_.Effect) ($($_.Cause))" } else { $_.Effect } }) -join ', '
                        $sync.EffectSeq++
                    }
                    if ($ev.ChaseEnd) { $sync.ChaseEndSeq++ }
                }
                $sync.Error = $null

                # Keep a short log of what the screen said, to tune detection later
                $flat = ($text -replace '\s+', ' ').Trim()
                if ($flat -and $flat -ne $lastFlat) {
                    $lastFlat = $flat
                    if ((Test-Path $logPath) -and (Get-Item $logPath).Length -gt 2MB) { Move-Item $logPath "$logPath.old" -Force }
                    $tag = if ($menuHits.Count -ge 2) { "MENU[$($menuHits -join ',')]" } elseif ($hit) { "MAP[$($hit.name)]" } elseif ($burst) { 'START' } else { '-' }
                    $line = $flat.Substring(0, [Math]::Min(400, $flat.Length))
                    Add-Content $logPath ("{0:HH:mm:ss} {1} {2}" -f (Get-Date), $tag, $line) -Encoding utf8
                }
            } catch { if ($_.Exception.Message -ne 'game window capture not available') { $sync.Error = $_.Exception.Message } }
            # Free the screenshot even when the scan failed half-way. (No forced
            # [GC]::Collect here any more - it froze the whole overlay, compass
            # included, for a moment every scan; Read-BitmapText reuses its buffer.)
            if ($bmp) { $bmp.Dispose(); $bmp = $null }
        } else { $sync.LoadoutNow = $false }   # not reading the screen = can't vouch for the loadout panel
        $sync.LastScan = Get-Date   # heartbeat for the status pill
        if ($saveStart) {
            # Diagnostic heartbeat, one line per scan (only while the flag file exists)
            if ((Test-Path $scanLog) -and (Get-Item $scanLog).Length -gt 1MB) { Move-Item $scanLog "$scanLog.old" -Force }
            $fgInfo = if ($sync.DbdInFront) { '' } else { Get-ForegroundInfo }
            Add-Content $scanLog ("{0:HH:mm:ss.f} front={1} bright={2:0.000} text={3} menu={4} burst={5} err={6} {7}" -f (Get-Date), $sync.DbdInFront, $brightness, $textLen, $menuHits.Count, $burst, $sync.Error, $fgInfo)
        }
        # Scan every ~1.5 s while looking for a map, every 3 s once one is up.
        # Holding TAB (match details shows the map name) triggers a scan straight away.
        $waitUntil = (Get-Date).AddMilliseconds($(if ($sync.HaveMap) { 3000 } elseif ($burst) { 400 } else { 1500 }))
        # In the lobby, between full reads: glance at the loadout panel's title
        # every 0.2 s (~10 ms each), so the SPIN button shows and hides with
        # the panel instead of up to ~2 s late (user, 2 Nov)
        $nextQuick = Get-Date
        while ((Get-Date) -lt $waitUntil -and -not $sync.ScanNow -and -not $sync.Quit) {
            $inLobby = $sync.LoadoutNow -or ($sync.LobbyAt -and ((Get-Date) - $sync.LobbyAt).TotalSeconds -lt 20)
            if ($inLobby -and (Get-Date) -ge $nextQuick -and $sync.Enabled -and -not $sync.Paused -and -not $testShot) {
                $nextQuick = (Get-Date).AddMilliseconds(200)
                try {
                    $front = Test-DbdInFront
                    $lo = $front -and (Test-LoadoutTitle)
                    $sync.DbdInFront = $front
                    if ($lo) { $sync.LoadoutAt = Get-Date }
                    $sync.LoadoutNow = $lo; $sync.LastScan = Get-Date
                } catch {}
            }
            Start-Sleep -Milliseconds 50
        }
        $tabScan = [bool]$sync.ScanNow   # this next scan is the TAB screen
        if ($sync.ScanNow) { Start-Sleep -Milliseconds 300; $sync.ScanNow = $false }
    }
})
$detectorHandle = $detector.BeginInvoke()

# ---------- Update check: once per start, asks GitHub for the newest release
# (a plain web request, nothing about you is sent) and compares it with
# VERSION. The note shows on the status label the first time you're in the
# lobby - never mid-match. ----------
$updTask = $null; $updNote = $null
$localVersion = try { [version]((Get-Content (Join-Path $root 'VERSION') -TotalCount 1 -ErrorAction Stop).Trim()) } catch { $null }
if ($localVersion -and -not ($env:DBD_OVERLAY_SPIN -or $env:DBD_OVERLAY_DEMO -or $env:DBD_OVERLAY_KILLER -or $env:DBD_OVERLAY_TESTSHOT)) {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $updClient = New-Object System.Net.WebClient
        $updClient.Headers.Add('User-Agent', 'DbD-Clock-Overlay')
        $updTask = $updClient.DownloadStringTaskAsync('https://api.github.com/repos/isJeffu/dbd-clock-overlay/releases/latest')
    } catch { $updTask = $null }
}
function Update-UpdateNote {
    if ($script:updTask -and $script:updTask.IsCompleted) {
        $t = $script:updTask; $script:updTask = $null
        if ($t.Status -eq 'RanToCompletion') {
            try {
                $tag = (($t.Result | ConvertFrom-Json).tag_name).TrimStart('v')
                if ([version]$tag -gt $localVersion) { $script:updNote = "Update v$tag available: Start menu > DbD Clock Overlay > Update" }
            } catch {}
        }
    }
    if ($script:updNote -and $sync.LobbyAt -and ((Get-Date) - $sync.LobbyAt).TotalSeconds -lt 5) {
        Show-Hint $script:updNote 10; $script:updNote = $null   # once per start
    }
}

# ---------- Tray icon ----------
$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon = [System.Drawing.SystemIcons]::Information
$tray.Text = 'DbD Clock Overlay'
$menu = New-Object System.Windows.Forms.ContextMenuStrip
[void]$menu.Items.Add('Pick map (F6)', $null, { Show-Picker })
[void]$menu.Items.Add('Pick your perks (PageUp)', $null, { Show-PerkPicker })
[void]$menu.Items.Add('Show / hide (F8)', $null, { Invoke-Hotkey 4 })
[void]$menu.Items.Add('Screenshot with overlay (PrintScreen)', $null, { Invoke-Hotkey 13 })
[void]$menu.Items.Add('Quit (Pause)', $null, { $window.Close() })
$tray.ContextMenuStrip = $menu
$tray.Visible = $true

# ---------- Hotkeys ----------
# PrintScreen: save a screenshot WITH the overlay in it. Normally the overlay hides
# itself from screenshots (so the map reader never reads its own text), so it
# turns that off for a moment, captures, then turns it back on. It never touches
# the game window (moving/restoring it can knock DbD out of borderless).
# Survey mode (survey.flag present): Insert saves a game picture + the raw mouse
# heading, for mapping landmarks. Look so the landmark is in the middle of the screen.
$surveyMode = Test-Path (Join-Path $root 'survey.flag')
function Save-SurveyPoint {
    try {
        $dir = Join-Path $root 'Screenshots\survey'
        New-Item -ItemType Directory -Force $dir | Out-Null
        $name = '{0:MMdd-HHmmss}.jpg' -f (Get-Date)
        $sb = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds   # overlay windows are excluded from captures
        $bmp = New-Object System.Drawing.Bitmap $sb.Width, $sb.Height
        $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($sb.Location, [System.Drawing.Point]::Empty, $sb.Size)
        # Paste the callout map top-left (the overlay itself is hidden from captures)
        if ($state.Map) {
            $mp = Join-Path $root "maps\$($state.Map.file)"
            if (Test-Path $mp) {
                $mi = [System.Drawing.Image]::FromFile($mp)
                $mh = [int]($sb.Height * 0.38); $mw = [int]($mi.Width * $mh / $mi.Height)
                $g.DrawImage($mi, 20, 20, $mw, $mh); $mi.Dispose()
            }
        }
        $g.Dispose()
        $bmp.Save((Join-Path $dir $name), [System.Drawing.Imaging.ImageFormat]::Jpeg); $bmp.Dispose()
        $deg = if ($state.CountsPer360) { [Math]::Round(([RawMouse]::TotalX / [double]$state.CountsPer360 * 360.0) % 360.0, 1) } else { '' }
        Add-Content (Join-Path $dir 'survey-log.txt') ("{0:yyyy-MM-dd HH:mm:ss}  counts={1}  deg={2}  per360={3}  map={4}  pic={5}" -f (Get-Date), [RawMouse]::TotalX, $deg, $state.CountsPer360, $(if ($state.Map) { $state.Map.name } else { '-' }), $name)
        $script:surveyCount++
        Show-Hint "Survey point $($script:surveyCount) saved" 2
    } catch { Show-Hint "Survey failed: $($_.Exception.Message)" 4 }
}
$surveyCount = 0

function Save-OverlayScreenshot {
    $sync.Paused = $true
    foreach ($w in $window, $pillWindow, $timerWindow, $killerWindow, $collapseWindow) {
        [void][OverlayNative]::SetWindowDisplayAffinity((New-Object System.Windows.Interop.WindowInteropHelper $w).Handle, 0)
    }
    $shot = New-Object System.Windows.Threading.DispatcherTimer
    $shot.Interval = [TimeSpan]::FromMilliseconds(400)
    $shot.Add_Tick({
        $this.Stop()
        try {
            $dir = Join-Path $root 'Screenshots'
            New-Item -ItemType Directory -Force $dir | Out-Null
            $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
            $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
            $g.Dispose()
            $path = Join-Path $dir ("DbD overlay {0:yyyy-MM-dd HH-mm-ss}.png" -f (Get-Date))
            $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
        } finally {
            foreach ($w in $window, $pillWindow, $timerWindow, $killerWindow, $collapseWindow) {
                [void][OverlayNative]::SetWindowDisplayAffinity((New-Object System.Windows.Interop.WindowInteropHelper $w).Handle, 0x11)
            }
            $sync.Paused = $false
        }
        Show-Hint 'Screenshot saved in the Screenshots folder' 4
    })
    $shot.Start()
}

function Invoke-Hotkey([int]$id) {
    switch ($id) {
        1 { Show-Picker }
        2 { $state.AutoDetect = -not $state.AutoDetect; $sync.Enabled = $state.AutoDetect
            $state.Visible = $true
            Show-Hint ("Auto-detect " + $(if ($state.AutoDetect) { 'ON' } else { 'OFF' })); Update-Layout; Save-Settings }
        3 { $state.Corner = ($state.Corner + 1) % $corners.Count; Update-Layout; Save-Settings }
        4 { $state.Visible = -not $state.Visible; Update-Layout; Update-Status }
        5 { $state.Opacity = ($state.Opacity + 1) % $opacities.Count; Update-Layout; Save-Settings }
        6 { $state.Size = ($state.Size + 1) % $heights.Count; Update-Layout; Save-Settings }
        7 { $window.Close() }
        { $_ -in 8, 10, 15 -or ($_ -eq 14 -and -not $script:surveyMode) } { if (-not $state.TimersOn) { Show-Hint 'Timers are off - "TimersOn": true in settings.json turns them on' 4; break } }
        8 { $n = Start-EventTimers 'unhook_you'; Show-Hint "F4: you unhooked someone - $n timer(s)" 3 }
        14 { if ($script:surveyMode) { Save-SurveyPoint } else { $n = Start-EventTimers 'unhooked'; Show-Hint "Insert: you were unhooked - $n timer(s)" 3 } }
        15 { if ((Start-EventTimers 'exhausted') -eq 0) { Show-Hint 'No exhaustion perk in your build (PageUp)' 3 } }
        16 { Show-PerkPicker }
        9 { Reset-Timers }
        10 { Switch-Chase }
        11 { $state.TimerPos = ($state.TimerPos + 1) % $timerGaps.Count; Save-Settings
             if (-not ($activeTimers.Count -or $chase.Start)) { Start-UnhookTimers }   # show them so you can see where they went
             Update-Timers }
        12 { $state.TimerSize = ($state.TimerSize + 1) % $timerScales.Count; Save-Settings
             if (-not ($activeTimers.Count -or $chase.Start)) { Start-UnhookTimers }
             Update-Timers }
        13 { Save-OverlayScreenshot }
        17 { Invoke-CompassKey 'north' }
        18 { Invoke-CompassKey 'calibrate' }
        19 { Invoke-CompassKey 'toggle' }
    }
}

# Keys. DbD blocks normal Windows hotkeys while it's in front, so instead the
# overlay just checks which keys are down (like the TAB check) - and only while
# DbD is the window in front, so F5 in your browser etc. does nothing here.
# The game still sees these keys too, so they must be ones DbD doesn't use:
# no F11 (it toggles fullscreen), no Alt combos.
$keyMap = @(
    # Plain keys only: Shift is "run" and Ctrl is "crouch" in DbD, so modifier
    # combinations misfire mid-match. These keys are unbound in the game.
    @{ Id = 19; Vk = 0x70; Name = 'F1' },           # compass: show / hide
    @{ Id = 17; Vk = 0x71; Name = 'F2' },           # compass: facing 12 now
    @{ Id = 15; Vk = 0x72; Name = 'F3' },           # used exhaustion perk
    @{ Id = 8;  Vk = 0x73; Name = 'F4' },           # you unhooked someone
    @{ Id = 10; Vk = 0x74; Name = 'F5' },           # chase start/stop
    @{ Id = 1;  Vk = 0x75; Name = 'F6' },           # pick map
    @{ Id = 3;  Vk = 0x76; Name = 'F7' },           # move map
    @{ Id = 4;  Vk = 0x77; Name = 'F8' },           # show/hide map
    @{ Id = 5;  Vk = 0x78; Name = 'F9' },           # see-through
    @{ Id = 6;  Vk = 0x79; Name = 'F10' },          # map size
    @{ Id = 14; Vk = 0x2D; Name = 'Insert' },       # you were unhooked (normally automatic)
    @{ Id = 9;  Vk = 0x2E; Name = 'Delete' },       # clear timers
    @{ Id = 11; Vk = 0x24; Name = 'Home' },         # timer position
    @{ Id = 12; Vk = 0x23; Name = 'End' },          # timer size
    @{ Id = 16; Vk = 0x21; Name = 'PageUp' },       # pick your perks
    @{ Id = 2;  Vk = 0x22; Name = 'PageDown' },     # auto-detect on/off
    @{ Id = 13; Vk = 0x2C; Name = 'PrintScreen' },  # screenshot with the overlay in it
    @{ Id = 18; Vk = 0x91; Name = 'ScrollLock' },   # compass: calibrate one full turn
    @{ Id = 7;  Vk = 0x13; Name = 'Pause' }         # quit the overlay
)
$keyWasDown = @{}
$dbdPid = 0
$keyDebug = Test-Path (Join-Path $root 'key-debug.flag')   # log every F-key press to overlay-errors.txt

function Test-KeyDown([int]$vk) { ([OverlayNative]::GetAsyncKeyState($vk) -band 0x8000) -ne 0 }

function Test-DbdFront {
    if (-not $script:dbdPid) { return $false }
    $fgPid = 0
    [void][OverlayNative]::GetWindowThreadProcessId([OverlayNative]::GetForegroundWindow(), [ref]$fgPid)
    $fgPid -eq $script:dbdPid
}

function Invoke-KeyPolling {
    $front = Test-DbdFront
    # compass: mouse moves on other windows, or on the TAB / Esc screens (cursor, not camera), don't count
    [RawMouse]::Enabled = $front -and -not $script:tabWasDown -and -not $sync.EscMenu
    foreach ($vk in ($keyMap | ForEach-Object { $_.Vk } | Select-Object -Unique)) {
        $down = Test-KeyDown $vk
        # F2: short tap = "facing 12", hold ~1 s = start / finish the calibration turn (fires on release)
        if ($vk -eq 0x71) {
            if ($down -and -not $keyWasDown[$vk]) { $script:f2DownAt = Get-Date }
            if (-not $down -and $keyWasDown[$vk] -and $front -and $script:f2DownAt) {
                $held = ((Get-Date) - $script:f2DownAt).TotalSeconds
                if ($script:keyDebug) { Add-Content (Join-Path $root 'overlay-errors.txt') ("{0:HH:mm:ss} F2 released after {1:0.00} s" -f (Get-Date), $held) }
                try { if ($held -ge 0.9) { Invoke-CompassKey 'calibrate' } else { Invoke-CompassKey 'north' } } catch {}
                $script:f2DownAt = $null
            }
            $keyWasDown[$vk] = $down
            continue
        }
        if ($down -and -not $keyWasDown[$vk] -and $script:keyDebug) {
            Add-Content (Join-Path $root 'overlay-errors.txt') ("{0:HH:mm:ss} keydown vk=0x{1:X} front={2} ctrl={3}" -f (Get-Date), $vk, $front, (Test-KeyDown 0x11))
        }
        if ($down -and -not $keyWasDown[$vk] -and $front) {
            $hit = $keyMap | Where-Object { $_.Vk -eq $vk } | Select-Object -First 1
            if ($hit) {
                if ($env:DBD_OVERLAY_DEBUG) { Add-Content (Join-Path $root 'overlay-errors.txt') ("{0:HH:mm:ss} key {1}" -f (Get-Date), $hit.Name) }
                # Errors inside timer handlers are otherwise silent - note them in a file
                try { Invoke-Hotkey $hit.Id } catch { Add-Content (Join-Path $root 'overlay-errors.txt') ("{0:HH:mm:ss} {1}: {2} at {3}" -f (Get-Date), $hit.Name, $_.Exception.Message, $_.InvocationInfo.PositionMessage) }
            }
        }
        $keyWasDown[$vk] = $down
    }
}
$ok = $true

# ---------- UI timer: pick up detections, keep on top ----------
$lastSeq = 0; $tick = 0; $lastPerkSeq = 0; $loggedErrors = @(); $lastRescueSeq = 0; $lastChaseEndSeq = 0; $lastAutoUnhook = $null; $lastUnhookedSeq = 0; $lastAutoUnhooked = $null; $lastCarriedSeq = 0; $lastDeadSeq = 0; $lastEffectSeq = 0; $lastKillerSeq = 0
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(500)

# Watch the TAB key (only reads whether it is down - never blocks or changes it)
$tabWasDown = $false
$keyTimer = New-Object System.Windows.Threading.DispatcherTimer
$keyTimer.Interval = [TimeSpan]::FromMilliseconds(50)
# Close by itself once Dead by Daylight has been running and then quits
$dbdSeen = $false; $dbdGoneSince = $null
$dbdTimer = New-Object System.Windows.Threading.DispatcherTimer
$dbdTimer.Interval = [TimeSpan]::FromSeconds(5)
$dbdTimer.Add_Tick({
    $game = Get-Process -Name 'DeadByDaylight*' -ErrorAction SilentlyContinue | Select-Object -First 1
    $script:dbdPid = if ($game) { $game.Id } else { 0 }
    if ($game) { $script:dbdSeen = $true; $script:dbdGoneSince = $null }
    elseif ($script:dbdSeen) {
        if (-not $script:dbdGoneSince) { $script:dbdGoneSince = Get-Date }
        elseif (((Get-Date) - $script:dbdGoneSince).TotalSeconds -ge 10) { $window.Close() }
    }
})

$keyTimer.Add_Tick({
    Update-Roulette   # every 50 ms: the SPIN button follows the loadout panel quickly
    $down = ([OverlayNative]::GetAsyncKeyState(0x09) -band 0x8000) -ne 0
    if ($down -and -not $script:tabWasDown) { $sync.ScanNow = $true }
    $script:tabWasDown = $down
    Invoke-KeyPolling
})

$timer.Add_Tick({
    $sync.HaveMap = [bool]$state.Map
    Update-Status
    Update-Collapse
    Update-UpdateNote

    # A map name was read (menus are already filtered out by the detector)
    if ($sync.Seq -ne $script:lastSeq) {
        $script:lastSeq = $sync.Seq
        $name = $sync.Detected
        # Once a map is up it stays for the match - only the TAB screen can swap it,
        # so stray text (e.g. "the game" in a report window) can't change it
        if (-not $state.Map -or ($state.Map.name -ne $name -and $sync.DetectedViaTab)) {
            Set-Map ($maps | Where-Object { $_.name -eq $name } | Select-Object -First 1)
        }
    }

    # Back in the lobby / menus (seen on two scans in a row) - put the map away
    # Detector problems are otherwise invisible - note each new one in the log file
    foreach ($err in @($sync.Error, $sync.PerkError)) {
        if ($err -and $script:loggedErrors -notcontains $err) { $script:loggedErrors += $err; Add-Content (Join-Path $root 'overlay-errors.txt') ("{0:HH:mm:ss} detector: {1}" -f (Get-Date), $err) }
    }

    # Perks read from the lobby diamonds - they become your build for the timers
    if ($sync.PerkSeq -ne $script:lastPerkSeq) {
        $script:lastPerkSeq = $sync.PerkSeq
        $state.Perks = @($sync.DetectedPerks); Save-Settings
        Show-Hint ('Perks: ' + ($state.Perks -join ', ')) 8
        Add-Content (Join-Path $root 'overlay-errors.txt') ("{0:HH:mm:ss} perks read: {1}" -f (Get-Date), ($sync.PerkScores -join '; '))
    }

    # You unhooked someone ("HOOK RESCUE" pop-up) - start the unhook timers.
    # The pop-up stays up for several scans, so only once per 30 s.
    if ($sync.RescueSeq -ne $script:lastRescueSeq) {
        $script:lastRescueSeq = $sync.RescueSeq
        if ($state.TimersOn -and (-not $script:lastAutoUnhook -or ((Get-Date) - $script:lastAutoUnhook).TotalSeconds -gt 30)) {
            $script:lastAutoUnhook = Get-Date
            $n = Start-EventTimers 'unhook_you'
            Show-Hint "You unhooked someone - $n timer(s)" 3
        }
    }
    # You were just unhooked (Endurance + Haste showed up in the status strip)
    if ($sync.UnhookedSeq -ne $script:lastUnhookedSeq) {
        $script:lastUnhookedSeq = $sync.UnhookedSeq
        if ($state.TimersOn -and (-not $script:lastAutoUnhooked -or ((Get-Date) - $script:lastAutoUnhooked).TotalSeconds -gt 30)) {
            $script:lastAutoUnhooked = Get-Date
            $src = @($sync.UnhookedSource)
            $n = Start-EventTimers 'unhooked' $src
            Show-Hint ("You were unhooked - $n timer(s)" + $(if ($src.Count) { " (" + ($src -join ', ') + ")" } else { '' })) 4
        }
    }
    # A status effect just appeared: say what and (as far as the screen says) why
    if ($sync.EffectSeq -ne $script:lastEffectSeq) {
        $script:lastEffectSeq = $sync.EffectSeq
        $fxText = [string]$sync.EffectText
        if ($fxText) {
            $nice = [Globalization.CultureInfo]::InvariantCulture.TextInfo.ToTitleCase($fxText.ToLowerInvariant())
            Show-Hint "Status: $nice" 5
            $log = Join-Path $root 'status-log.txt'
            if ((Test-Path $log) -and (Get-Item $log).Length -gt 200KB) { Move-Item $log "$log.old" -Force }
            Add-Content $log ("{0:yyyy-MM-dd HH:mm:ss} {1}  map={2}" -f (Get-Date), $nice, $(if ($state.Map) { $state.Map.name } else { '-' }))
        }
    }
    # The Esc screen named the killer: show their cheat card, once per match
    # SHELVED (19 Oct): user wants survivor-side focus for now - card code and killers.json kept, set $true to re-enable
    if ($script:killerCardOn -and $sync.KillerSeq -ne $script:lastKillerSeq) {
        $script:lastKillerSeq = $sync.KillerSeq
        $kt = [string]$sync.KillerTitle
        if ($kt -and $script:killerShown -notcontains $kt) {
            if (Show-KillerCard $kt) { $script:killerShown += $kt }
        }
    }
    if ($script:killerUntil -and (Get-Date) -ge $script:killerUntil) { $script:killerUntil = $null; $killerWindow.Hide() }
    # Picked up by the killer: the compass heading is meaningless from here on
    if ($sync.CarriedSeq -ne $script:lastCarriedSeq) {
        $script:lastCarriedSeq = $sync.CarriedSeq
        if ($null -ne $compass.NorthCounts) {
            $compass.NorthCounts = $null; Update-Compass
            Show-Hint 'Compass reset (picked up) - F2 when facing 12 once you are free' 5
        }
    }
    # Your match is over (died / escaped): compass off until the next map
    if ($sync.DeadSeq -ne $script:lastDeadSeq) {
        $script:lastDeadSeq = $sync.DeadSeq
        if ($null -ne $compass.NorthCounts) { $compass.NorthCounts = $null; Update-Compass }
    }
    # A chase just ended ("CHASED" / "ESCAPED" pop-up) - stop the chase timer if it's running
    if ($sync.ChaseEndSeq -ne $script:lastChaseEndSeq) {
        $script:lastChaseEndSeq = $sync.ChaseEndSeq
        if ($chase.Start) { Switch-Chase }
    }

    if ($sync.MenuStreak -ge 2 -and $state.Map) {
        $state.Map = $null; $image.Source = $null
        $tray.Text = 'DbD Clock Overlay'
        Update-Layout; Update-Status
    }
    # Match over: drop running timers once, when the menus first appear - not
    # all the time, so F4/F5 still work in the lobby
    $inMenus = $sync.MenuStreak -ge 2
    if ($inMenus -and -not $script:wasInMenus) { Reset-Timers; $script:killerShown = @() }
    $script:wasInMenus = $inMenus

    # Games can push themselves on top - re-assert every 2 s
    $script:tick++
    if ($script:tick % 4 -eq 0) {
        foreach ($w in $window, $pillWindow, $timerWindow, $killerWindow, $collapseWindow) {
            $h = (New-Object System.Windows.Interop.WindowInteropHelper $w).Handle
            if ($h -ne [IntPtr]::Zero) { [void][OverlayNative]::SetWindowPos($h, [IntPtr](-1), 0, 0, 0, 0, 0x0013) }
        }
    }
})

$window.Add_Closed({
    $timer.Stop(); $keyTimer.Stop(); $dbdTimer.Stop()
    $sync.Quit = $true
    if ($script:picker) { $script:picker.Close() }
    $pillWindow.Close(); $killerWindow.Close(); $collapseWindow.Close(); $rlWindow.Close(); $rlBtnWindow.Close(); $timerWindow.Close(); $compassWindow.Close(); $timerTick.Stop()
    $tray.Visible = $false; $tray.Dispose()
    try { [void]$detectorHandle.AsyncWaitHandle.WaitOne(4000); $detector.Dispose(); $runspace.Close() } catch {}
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown()
})

$startHint = 'Clock overlay started - F6 pick map, F7 move, F8 hide'
Show-Hint $startHint 8
Update-Layout
$timer.Start()
$keyTimer.Start(); $dbdTimer.Start()
$pillWindow.Show()
$timerWindow.Show(); Update-Timers; $timerTick.Start()
$window.Show()
$compassWindow.Show(); Start-Compass; Update-Compass
Update-Layout
# Demo mode (for testing): a random map with auto-detect paused, not saved
if ($env:DBD_OVERLAY_DEMO) {
    $state.AutoDetect = $false; $sync.Enabled = $false
    # DBD_OVERLAY_DEMO=<map name> picks that map; DBD_OVERLAY_RENDER=<png> saves the map window and quits (testing)
    $pick = $maps | Where-Object { $_.name -eq $env:DBD_OVERLAY_DEMO } | Select-Object -First 1
    Set-Map $(if ($pick) { $pick } else { $maps | Get-Random })
    if ($env:DBD_OVERLAY_RENDER) {
        $window.UpdateLayout()
        $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap ([int]$mapGrid.ActualWidth), ([int]$mapGrid.ActualHeight), 96, 96, ([System.Windows.Media.PixelFormats]::Pbgra32)
        $rtb.Render($mapGrid)
        $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
        $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
        $fs = [IO.File]::Create($env:DBD_OVERLAY_RENDER); $enc.Save($fs); $fs.Close()
        $window.Close()
    }
}
# Killer card test: DBD_OVERLAY_KILLER=<title, e.g. THE PIG> shows that card;
# with DBD_OVERLAY_RENDER=<png> it saves the card and quits
if ($env:DBD_OVERLAY_KILLER) {
    $state.AutoDetect = $false; $sync.Enabled = $false
    if (-not (Show-KillerCard $env:DBD_OVERLAY_KILLER.ToUpperInvariant())) { Show-Hint "No killer card for '$($env:DBD_OVERLAY_KILLER)'" 8 }
    elseif ($env:DBD_OVERLAY_RENDER) {
        $killerWindow.UpdateLayout()
        $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap ([int]$killerCard.ActualWidth), ([int]$killerCard.ActualHeight), 96, 96, ([System.Windows.Media.PixelFormats]::Pbgra32)
        $rtb.Render($killerCard)
        $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
        $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
        $fs = [IO.File]::Create($env:DBD_OVERLAY_RENDER); $enc.Save($fs); $fs.Close()
        $window.Close()
    }
}
# Perk roulette test: DBD_OVERLAY_SPIN=1 shows the roulette and spins it (sound
# included); with DBD_OVERLAY_RENDER=<png> it saves <png>-mid.png during the spin
# and <png> once it has stopped, then quits
if ($env:DBD_OVERLAY_SPIN) {
    $state.AutoDetect = $false; $sync.Enabled = $false
    # DBD_OVERLAY_SPIN=button: show the button only and wait for a real click
    Update-Roulette; if ($env:DBD_OVERLAY_SPIN -ne 'button') { Start-PerkSpin }
    $rlTestStart = Get-Date; $rlTestMid = $false
    $rlTest = New-Object System.Windows.Threading.DispatcherTimer
    $rlTest.Interval = [TimeSpan]::FromMilliseconds(100)
    $rlTest.Add_Tick({
        if (-not $env:DBD_OVERLAY_RENDER) { $this.Stop(); return }
        if ($env:DBD_OVERLAY_SPIN -eq 'button' -and -not $script:rlClicked) {
            if ($script:rlSpinning) { $script:rlClicked = $true; $script:rlTestStart = Get-Date }
            elseif (((Get-Date) - $script:rlTestStart).TotalSeconds -gt 20) { $this.Stop(); $window.Close() }
            return
        }
        $age = ((Get-Date) - $script:rlTestStart).TotalSeconds
        if (-not $script:rlTestShots) { $script:rlTestShots = @{} }
        # three moments: spinning, all locked on the slots, in the cluster
        foreach ($m in @(@{ T = 1.3; N = 'mid' }, @{ T = 4.0; N = 'locked' }, @{ T = 5.6; N = 'final' })) {
            if ($age -lt $m.T -or $script:rlTestShots[$m.N]) { continue }
            $script:rlTestShots[$m.N] = $true
            $base = $env:DBD_OVERLAY_RENDER -replace '\.png$', ''
            Save-RouletteRender "$base-$($m.N).png"
            foreach ($part in @(@{ E = $rlButton; S = '-button' })) {
                $part.E.UpdateLayout()
                $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap ([int][Math]::Max(1, $part.E.ActualWidth)), ([int][Math]::Max(1, $part.E.ActualHeight)), 96, 96, ([System.Windows.Media.PixelFormats]::Pbgra32)
                $rtb.Render($part.E)
                $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
                $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
                $fs = [IO.File]::Create("$base-$($m.N)$($part.S).png"); $enc.Save($fs); $fs.Close()
            }
            # where the two windows sit, for pasting onto a screenshot
            @{ Unit = $rlU; ScreenW = [System.Windows.SystemParameters]::PrimaryScreenWidth; ScreenH = [System.Windows.SystemParameters]::PrimaryScreenHeight
               ReelLeft = 290 * $rlU; ReelTop = 200 * $rlU; BtnLeft = $rlBtnWindow.Left; BtnTop = $rlBtnWindow.Top } | ConvertTo-Json | Set-Content "$base-pos.json"
            if ($m.N -eq 'final') { $this.Stop(); $window.Close() }
        }
    })
    $rlTest.Start()
}
[System.Windows.Threading.Dispatcher]::Run()