# Perk roulette for the LOADOUT screen. A small SPIN button sits above your
# perk row, centred over slots 2 and 3. Click it: four diamond reels spin right on top of
# your slots, lock in left to right (with a mechanical clunk), then shrink and
# slide into a list on the right - each perk's diamond with its name beside
# it - so your real slots are free to click. It only SHOWS a build: equip the
# perks yourself; the lobby perk reader picks up what you equip, as usual.
# The result stays while the loadout is open, comes back if you reopen the
# loadout before the match, and is cleared once a match starts.
# Dot-sourced by ClockOverlay.ps1 after Timers.ps1 ($perkDb, New-OverlayWindow,
# OverlayNative). Styled like DbD's own slots and READY button.
#
# Layout: measured on the loadout screen at 1080p and scaled by screen HEIGHT
# (DbD's menus scale with height and sit against the left edge), so it lines up
# at 1080p / 1440p / 4K and any Windows scaling. If DbD's own UI scale setting
# is changed from 100%, the slots move and this won't line up.

$rlSlotX = @(360, 528, 696, 866)    # perk slot centres (1080p pixels)
$rlSlotY = 426
# The reel must also hide the slot's 3 white tier pips (top right, outside the
# diamond), so it's bigger than the slot and its centre sits 6 px up-right.
# Checked against the 1080p slot: all four tips and the pips fall inside.
$rlHalf  = 72
$rlShiftX = 6; $rlShiftY = -6
# Result list (1080p pixels): rows of diamond + name, right of the slots
$rlRowScale = 0.62                  # result diamonds = 0.62 x the reel (bigger than the old cluster)
$rlRowGap   = 6
$rlListPad  = 10
$rlListX    = 1062                  # left edge of the list panel (just past the loadout panel, clear of SEARCH)
$rlNameW    = 220                   # room for the names
$rlNameSize = 18                    # name text size
$rlSpins = @(1.8, 2.4, 3.0, 3.6)    # seconds each reel spins
$rlStrip = 30                       # icons that roll past per spin
$rlGold  = [System.Windows.Media.Color]::FromRgb(232, 190, 80)
$rlDim   = [System.Windows.Media.Color]::FromRgb(120, 96, 40)

# ---- Sounds: made right here (no downloads), cached in the sounds folder ----
function Save-RouletteWav([string]$path, [double[]]$s) {
    $ms = New-Object System.IO.MemoryStream; $bw = New-Object System.IO.BinaryWriter $ms; $n = $s.Count
    $bw.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $bw.Write([int](36 + $n * 2)); $bw.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
    $bw.Write([int]16); $bw.Write([int16]1); $bw.Write([int16]1); $bw.Write([int]44100); $bw.Write([int](44100 * 2)); $bw.Write([int16]2); $bw.Write([int16]16)
    $bw.Write([Text.Encoding]::ASCII.GetBytes('data')); $bw.Write([int]($n * 2))
    foreach ($v in $s) { $bw.Write([int16]([Math]::Max(-32767, [Math]::Min(32767, $v * 32767)))) }
    $bw.Flush(); [IO.File]::WriteAllBytes($path, $ms.ToArray()); $bw.Dispose()
}
$rlSoundDir = Join-Path $root 'sounds'
$rlTickWav = Join-Path $rlSoundDir 'roulette-tick.wav'
$rlLockWav = Join-Path $rlSoundDir 'roulette-clunk.wav'
try {
    New-Item -ItemType Directory -Force $rlSoundDir | Out-Null
    if (-not (Test-Path $rlTickWav)) {
        # short bright tick
        $a = New-Object double[] 1323
        for ($i = 0; $i -lt $a.Count; $i++) { $t = $i / 44100; $a[$i] = 0.35 * [Math]::Exp(-$t * 160) * [Math]::Min(1, $i / 40.0) * ([Math]::Sin(2 * [Math]::PI * 2600 * $t) + [Math]::Sin(2 * [Math]::PI * 3900 * $t)) / 2 }
        Save-RouletteWav $rlTickWav $a
    }
    if (-not (Test-Path $rlLockWav)) {
        # reel clunk (the user's pick, 2 Nov): low falling thump + a short click of noise
        $rnd = New-Object Random 7
        $a = New-Object double[] 11025
        for ($i = 0; $i -lt $a.Count; $i++) { $t = $i / 44100; $a[$i] = 0.6 * [Math]::Exp(-$t * 28) * [Math]::Sin(2 * [Math]::PI * (140 - 60 * $t) * $t) + 0.25 * [Math]::Exp(-$t * 220) * ($rnd.NextDouble() * 2 - 1) }
        Save-RouletteWav $rlLockWav $a
    }
} catch {}
function New-RoulettePlayers([string]$wav, [int]$count, [double]$volume) {
    @(1..$count | ForEach-Object {
        $p = New-Object System.Windows.Media.MediaPlayer
        $p.Volume = $volume
        if (Test-Path $wav) { $p.Open((New-Object System.Uri $wav)) }
        $p
    })
}
# Ticks (dozens per spin) use Windows' lightweight sound player: one call, no
# work for the animation thread. The clunks keep MediaPlayer so they can
# overlap the ticks.
$rlTickSound = $null
try { $rlTickSound = New-Object System.Media.SoundPlayer $rlTickWav; $rlTickSound.Load() } catch {}
$rlLocks = New-RoulettePlayers $rlLockWav 3 0.8
# Warm-up: the first play of a sound loads Windows' media pipeline, which froze
# the reels for a moment as the first perk landed (user, 2 Nov). Play every
# player once, muted, at start-up so that happens here instead.
foreach ($p in @($rlLocks)) { $p.IsMuted = $true; $p.Play() }
$rlWarm = New-Object System.Windows.Threading.DispatcherTimer
$rlWarm.Interval = [TimeSpan]::FromSeconds(2)
$rlWarm.Add_Tick({ $this.Stop(); foreach ($p in @($rlLocks)) { $p.Stop(); $p.IsMuted = $false } })
$rlWarm.Start()
# Animations run at the monitor's refresh rate (WPF's default is 60 fps, which
# looked stuttery on a 144 Hz screen - user, 2 Nov)
$rlFps = 60
try { $hz = @(Get-CimInstance Win32_VideoController -ErrorAction Stop | ForEach-Object { [int]$_.CurrentRefreshRate } | Where-Object { $_ -gt 0 }) | Measure-Object -Maximum; if ($hz.Maximum -ge 60) { $rlFps = [int]$hz.Maximum } } catch {}
function Set-RouletteFps($timeline) { [System.Windows.Media.Animation.Timeline]::SetDesiredFrameRate($timeline, $rlFps); $timeline }
# Also preload the perk icons in small batches (the first spin used to load
# them all at once when you clicked)
# Reel icons get their own full-size (256 px) decode: the timers' 128 px copies
# blur at the reel's size on a 4K screen
$rlIconCache = @{}
function Get-RouletteIcon([string]$file) {
    if (-not $file) { return $null }
    if (-not $rlIconCache.ContainsKey($file)) {
        $path = Join-Path $root "icons\$file"
        $rlIconCache[$file] = if (Test-Path $path) {
            $bi = New-Object System.Windows.Media.Imaging.BitmapImage
            $bi.BeginInit(); $bi.UriSource = New-Object System.Uri $path; $bi.CacheOption = 'OnLoad'; $bi.EndInit(); $bi.Freeze()
            $bi
        } else { $null }
    }
    $rlIconCache[$file]
}
$rlIconQueue = New-Object System.Collections.Queue
foreach ($pk in @($perkDb.perks)) { $rlIconQueue.Enqueue($pk.file) }
$rlIconWarm = New-Object System.Windows.Threading.DispatcherTimer
$rlIconWarm.Interval = [TimeSpan]::FromMilliseconds(150)
$rlIconWarm.Add_Tick({
    for ($n = 0; $n -lt 12 -and $rlIconQueue.Count; $n++) { [void](Get-RouletteIcon $rlIconQueue.Dequeue()) }
    if (-not $rlIconQueue.Count) { $this.Stop() }
})
$rlIconWarm.Start()
$rlLockNext = 0
function Invoke-RouletteSound([string]$which) {
    if ($env:DBD_OVERLAY_QUIET) { return }   # tests
    try {
        if ($which -eq 'tick') { if ($rlTickSound) { $rlTickSound.Play() }; return }
        $p = $rlLocks[$script:rlLockNext]; $script:rlLockNext = ($script:rlLockNext + 1) % $rlLocks.Count
        $p.Stop(); $p.Position = [TimeSpan]::Zero; $p.Play()
    } catch {}
}

# ---- Scale: 1080p pixels -> WPF units on this screen. The loadout panel is
# pinned to the LEFT edge (UiLayout.ps1), so everything here is placed from
# the DbD UI's left / top ($rlX0, $rlY0 - 0 on 16:9 and ultrawide) ----
$rlUi = Get-DbdUi ([System.Windows.SystemParameters]::PrimaryScreenWidth) ([System.Windows.SystemParameters]::PrimaryScreenHeight) $(if ($state) { $state.UiLayout } else { 'auto' })
$rlU = $rlUi.U; $rlX0 = $rlUi.Left; $rlY0 = $rlUi.Top
$rlOff = if ($env:DBD_OVERLAY_OFFSCREEN) { -20000 } else { 0 }   # tests: keep it off your screen

# ---- DbD look (user, 2 Nov: "match DbD's theme"): slots are mottled purple
# with a thick black rim and a soft shadow down-left; buttons are black with a
# blood-red smear and bold white text; panels are dark with a thin grey edge ----
$rlPurpleTop = [System.Windows.Media.Color]::FromRgb(118, 72, 136)
$rlPurpleBot = [System.Windows.Media.Color]::FromRgb(74, 42, 90)
$rlRimCol    = [System.Windows.Media.Color]::FromRgb(10, 8, 14)
$rlWhite     = [System.Windows.Media.Color]::FromRgb(240, 240, 240)
$rlEdge      = [System.Windows.Media.Color]::FromRgb(78, 78, 82)
# DbD's menus use Roboto (READY / BACK bold, SEARCH regular). It ships in the
# fonts folder (Apache licence; copied from the Epic launcher's Unreal fonts).
$rlFont      = New-Object System.Windows.Media.FontFamily ([Uri]((Join-Path $root 'fonts') + '\')), './#Roboto, Segoe UI'
$rlFrameCol  = [System.Windows.Media.Color]::FromRgb(196, 196, 196)   # the worn grey line inside DbD's boxes
# a light grey line set a few px inside a black box, with small nicks in it,
# like the frame of DbD's SEARCH box / BACK button
function New-RouletteFrame([double]$inset) {
    $f = New-Object System.Windows.Shapes.Rectangle
    $f.Stroke = New-Object System.Windows.Media.SolidColorBrush $rlFrameCol
    $f.StrokeThickness = 1.5 * $rlU
    $f.StrokeDashArray = New-Object System.Windows.Media.DoubleCollection (,[double[]](16, 0.6, 7, 0.5, 23, 0.7, 10, 0.5))
    $f.Margin = New-Object System.Windows.Thickness ($inset * $rlU)
    $f.IsHitTestVisible = $false
    $f
}

# ---- Result list geometry (1080p pixels) ----
$rlRowHalf = $rlHalf * $rlRowScale                    # half-diagonal of a result diamond
$rlRowH    = 2 * $rlRowHalf + $rlRowGap
$rlListH   = 4 * $rlRowH - $rlRowGap + 2 * $rlListPad
$rlListY   = $rlSlotY - $rlListH / 2                  # vertically centred on the slots
$rlListW   = $rlListPad + 2 * $rlRowHalf + 14 + $rlNameW + $rlListPad
function Get-RouletteRowCentre([int]$i) { @(($rlListX + $rlListPad + $rlRowHalf), ($rlListY + $rlListPad + $rlRowHalf + $i * $rlRowH)) }
function Get-RouletteSlotCentre([int]$i) { @(($rlSlotX[$i] + $rlShiftX), ($rlSlotY + $rlShiftY)) }

# ---- Windows. A see-through window is redrawn whole every frame, so nothing
# moving lives in a big one (the old shared reel window covered slots + list
# during the slide and lagged - user, 2 Nov). Each reel has its own small
# window that is MOVED during the slide; the list panel + names sit in a
# window of their own that only redraws while fading. All click-through. ----
# The list window covers this area (1080p pixels):
$rlListAreaX = 1056; $rlListAreaY = 220; $rlListAreaW = 349; $rlListAreaH = 412
$rlListWin = New-OverlayWindow 'DbD Clock Overlay roulette list'
$rlListWin.SizeToContent = 'Manual'
$rlListWin.Width = $rlListAreaW * $rlU; $rlListWin.Height = $rlListAreaH * $rlU
$rlListCanvas = New-Object System.Windows.Controls.Canvas
$rlListCanvas.Width = $rlListAreaW * $rlU; $rlListCanvas.Height = $rlListAreaH * $rlU
$rlListWin.Content = $rlListCanvas

$rlListPanel = New-Object System.Windows.Controls.Border
$rlListPanel.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(215, 8, 8, 9))
$rlListPanel.Child = New-RouletteFrame 4
$rlListPanel.Width = $rlListW * $rlU; $rlListPanel.Height = $rlListH * $rlU
[System.Windows.Controls.Canvas]::SetLeft($rlListPanel, ($rlListX - $rlListAreaX) * $rlU)
[System.Windows.Controls.Canvas]::SetTop($rlListPanel, ($rlListY - $rlListAreaY) * $rlU)
$rlListPanel.Opacity = 0
[void]$rlListCanvas.Children.Add($rlListPanel)

function New-DiamondGeometry([double]$size, [double]$inset) {
    $h = $size / 2
    $g = New-Object System.Windows.Media.StreamGeometry
    $ctx = $g.Open()
    $ctx.BeginFigure((New-Object System.Windows.Point $h, $inset), $true, $true)
    $pts = New-Object 'System.Collections.Generic.List[System.Windows.Point]'
    $pts.Add((New-Object System.Windows.Point ($size - $inset), $h))
    $pts.Add((New-Object System.Windows.Point $h, ($size - $inset)))
    $pts.Add((New-Object System.Windows.Point $inset, $h))
    $ctx.PolyLineTo($pts, $true, $true); $ctx.Close(); $g.Freeze()
    $g
}

$rlD = 2 * $rlHalf * $rlU          # reel diamond size (WPF units)
# icon fills the reel the way the game's art fills a bare slot: 94 px art in a
# slot of half-diagonal 55 (1080p), scaled up to the reel's half-diagonal
$rlIcon = 94 * ($rlHalf / 55.0) * $rlU
$rlPitch = [Math]::Max($rlD * 0.78, $rlIcon * 1.06)   # distance between icons on a reel (no overlap)
$rlPad = 14                        # room round a reel in its window: the lock "pop" (1.1x) and the shadow (1080p px)
$rlCellWin = 2 * $rlHalf + 2 * $rlPad
$rlSlotTex = $null
try {
    $texPath = Join-Path $root 'textures\perk-slot.png'
    if (Test-Path $texPath) {
        $rlSlotTex = New-Object System.Windows.Media.Imaging.BitmapImage
        $rlSlotTex.BeginInit(); $rlSlotTex.UriSource = New-Object System.Uri $texPath; $rlSlotTex.CacheOption = 'OnLoad'; $rlSlotTex.EndInit(); $rlSlotTex.Freeze()
    }
} catch { $rlSlotTex = $null }
$rlReelsUi = @()
for ($i = 0; $i -lt 4; $i++) {
    $reelWin = New-OverlayWindow "DbD Clock Overlay roulette reel $($i + 1)"
    $reelWin.SizeToContent = 'Manual'
    $reelWin.Width = $rlCellWin * $rlU; $reelWin.Height = $rlCellWin * $rlU
    $root2 = New-Object System.Windows.Controls.Canvas
    $root2.Width = $reelWin.Width; $root2.Height = $reelWin.Height
    $reelWin.Content = $root2
    $cell = New-Object System.Windows.Controls.Canvas
    $cell.Width = $rlD; $cell.Height = $rlD
    [System.Windows.Controls.Canvas]::SetLeft($cell, $rlPad * $rlU); [System.Windows.Controls.Canvas]::SetTop($cell, $rlPad * $rlU)
    $cell.RenderTransformOrigin = '0.5,0.5'
    $scale = New-Object System.Windows.Media.ScaleTransform 1, 1
    $cell.RenderTransform = $scale
    # soft shadow down-left, like the game's slots
    $sh = New-Object System.Windows.Shapes.Path
    $sh.Data = New-DiamondGeometry $rlD 0
    $sh.Fill = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(110, 0, 0, 0))
    $sh.RenderTransform = New-Object System.Windows.Media.TranslateTransform (-5 * $rlU), (6 * $rlU)
    [void]$cell.Children.Add($sh)
    # purple slot: the game's grungy purple with dark specks and scratches
    # (textures\perk-slot.png, made by dev\make-slot-texture.ps1), mirrored
    # differently per reel so the four don't look identical; plain gradient if
    # the texture is missing
    $bg = New-Object System.Windows.Shapes.Path
    $bg.Data = New-DiamondGeometry $rlD 0
    if ($rlSlotTex) {
        $tb = New-Object System.Windows.Media.ImageBrush $rlSlotTex
        $fx = if ($i % 2) { -1.0 } else { 1.0 }; $fy = if ($i -ge 2) { -1.0 } else { 1.0 }
        $tb.RelativeTransform = New-Object System.Windows.Media.ScaleTransform $fx, $fy, 0.5, 0.5
        $tb.Freeze(); $bg.Fill = $tb
    } else { $bg.Fill = New-Object System.Windows.Media.LinearGradientBrush $rlPurpleTop, $rlPurpleBot, 90 }
    [void]$cell.Children.Add($bg)
    # the rolling strip, clipped to the diamond
    $win = New-Object System.Windows.Controls.Canvas
    $win.Width = $rlD; $win.Height = $rlD
    $win.Clip = New-DiamondGeometry $rlD (3 * $rlU)
    $strip = New-Object System.Windows.Controls.StackPanel
    $move = New-Object System.Windows.Media.TranslateTransform 0, 0
    $strip.RenderTransform = $move
    [void]$win.Children.Add($strip)
    [void]$cell.Children.Add($win)
    # thick black rim; flashes white as the reel locks (the game's "selected" look)
    $rimBrush = New-Object System.Windows.Media.SolidColorBrush $rlRimCol
    $rim = New-Object System.Windows.Shapes.Path
    # game's rim: 6.4 px on a bare slot (half-diagonal 55, 1080p), scaled to the reel like the icons
    $rimW = 6.4 * ($rlHalf / 55.0)
    $rim.Data = New-DiamondGeometry $rlD ($rimW / 2 * $rlU)
    $rim.Stroke = $rimBrush
    $rim.StrokeThickness = $rimW * $rlU; $rim.StrokeLineJoin = 'Miter'
    [void]$cell.Children.Add($rim)
    $cell.Visibility = 'Hidden'
    [void]$root2.Children.Add($cell)
    # its name, beside its row in the list (in the list window)
    $name = New-Object System.Windows.Controls.TextBlock
    $name.FontFamily = $rlFont; $name.FontWeight = 'Bold'; $name.FontSize = $rlNameSize * $rlU
    $name.Foreground = New-Object System.Windows.Media.SolidColorBrush $rlWhite
    $name.Width = $rlNameW * $rlU; $name.TextWrapping = 'Wrap'
    $name.Opacity = 0
    [void]$rlListCanvas.Children.Add($name)
    $slotC = Get-RouletteSlotCentre $i
    $rlReelsUi += @{ Win = $reelWin; Root = $root2; Cell = $cell; Scale = $scale; Strip = $strip; Move = $move; RimBrush = $rimBrush; Name = $name
                     Last = $null; Index = 0; Done = $true; Target = 0; CX = $slotC[0]; CY = $slotC[1]; S = 1.0; Hwnd = [IntPtr]::Zero; PX = $null; PY = $null }
}

# Put a reel's window so the diamond's centre is at (cx, cy) in 1080p pixels,
# at the given size. Once the window is up it's moved with one SetWindowPos
# (setting Left then Top would move it twice per frame).
$rlDpi = 0
function Set-ReelAt($r, [double]$cx, [double]$cy, [double]$s) {
    $r.CX = $cx; $r.CY = $cy; $r.S = $s
    $r.Scale.ScaleX = $s; $r.Scale.ScaleY = $s
    $x = ($cx - $rlHalf - $rlPad) * $rlU + $rlX0 + $rlOff; $y = ($cy - $rlHalf - $rlPad) * $rlU + $rlY0
    if ($r.Win.IsVisible) {
        if ($r.Hwnd -eq [IntPtr]::Zero) { $r.Hwnd = (New-Object System.Windows.Interop.WindowInteropHelper $r.Win).Handle }
        if (-not $script:rlDpi) { $script:rlDpi = [System.Windows.Media.VisualTreeHelper]::GetDpi($r.Win).DpiScaleX }
        $px = [int][Math]::Round($x * $rlDpi); $py = [int][Math]::Round($y * $rlDpi)
        if ($px -eq $r.PX -and $py -eq $r.PY) { return }   # hasn't moved a whole pixel
        $r.PX = $px; $r.PY = $py
        # no size / no z-order change / no activate
        [void][OverlayNative]::SetWindowPos($r.Hwnd, [IntPtr]::Zero, $px, $py, 0, 0, 0x0001 -bor 0x0004 -bor 0x0010)
    } else { $r.Win.Left = $x; $r.Win.Top = $y; $r.PX = $null }
}
# names: left edge just right of the row's diamond, centred on it vertically
function Set-RouletteNames {
    for ($i = 0; $i -lt 4; $i++) {
        $r = $rlReelsUi[$i]; $c = Get-RouletteRowCentre $i
        $r.Name.Text = if ($r.Last) { $r.Last.name.ToUpper() } else { '' }
        $r.Name.Measure([System.Windows.Size]::new($rlNameW * $rlU, [double]::PositiveInfinity))
        [System.Windows.Controls.Canvas]::SetLeft($r.Name, ($c[0] + $rlRowHalf + 14 - $rlListAreaX) * $rlU)
        [System.Windows.Controls.Canvas]::SetTop($r.Name, ($c[1] - $rlListAreaY) * $rlU - $r.Name.DesiredSize.Height / 2)
    }
}

# ---- SPIN button: clickable, but never takes focus from the game ----
$rlBtnWindow = New-Object System.Windows.Window
$rlBtnWindow.WindowStyle = 'None'; $rlBtnWindow.AllowsTransparency = $true
$rlBtnWindow.Background = [System.Windows.Media.Brushes]::Transparent
$rlBtnWindow.Topmost = $true; $rlBtnWindow.ShowInTaskbar = $false; $rlBtnWindow.ShowActivated = $false
$rlBtnWindow.SizeToContent = 'WidthAndHeight'; $rlBtnWindow.Title = 'DbD Clock Overlay roulette button'
$rlBtnWindow.Add_SourceInitialized({
    param($s, $e)
    $h = (New-Object System.Windows.Interop.WindowInteropHelper $s).Handle
    $ex = [OverlayNative]::GetWindowLong($h, -20)
    [void][OverlayNative]::SetWindowLong($h, -20, ($ex -bor 0x80 -bor 0x08000000))   # tool window, no-activate, NOT click-through
    [void][OverlayNative]::SetWindowDisplayAffinity($h, 0x11)
})
$rlButton = New-Object System.Windows.Controls.Border
# a short bar ABOVE the perk row, centred over slots 2-3 (user, 2 Nov: "above
# them, not between them"); sits in the strip between the divider line and the slots
$rlBtnW = 104; $rlBtnH = 30; $rlBtnCX = 612.6; $rlBtnCY = 352   # = bare slots 2/3 midpoint (user's pick 2 Nov, over the spinning-reel middle 618.6)
$rlButton.Width = $rlBtnW * $rlU; $rlButton.Height = $rlBtnH * $rlU
# Windows won't make a window narrower than ~130 px, so pin the button to the
# window's top-left corner (centred, it sat ~25 px right of the gap)
$rlButton.HorizontalAlignment = 'Left'; $rlButton.VerticalAlignment = 'Top'
$rlButton.Cursor = [System.Windows.Input.Cursors]::Hand
# styled like the game's own boxes (SEARCH, BACK [ESC]): black, a worn light
# grey line just inside the edge, Roboto Bold in light grey. Hover (user, 2
# Nov: "keep it black and white, the gradient moves with your mouse"): a soft
# white glow centred under the pointer, following it across the button.
$rlButton.BorderBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(24, 24, 26)); $rlButton.BorderThickness = 1 * $rlU
$rlBtnBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(240, 10, 10, 11))
$rlBtnHover = New-Object System.Windows.Media.RadialGradientBrush
$rlBtnHover.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.Color]::FromArgb(245, 92, 92, 96)), 0))
$rlBtnHover.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.Color]::FromArgb(242, 34, 34, 37)), 0.55))
$rlBtnHover.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.Color]::FromArgb(240, 10, 10, 11)), 1))
# a round-ish spot on a wide button: radius as a share of the button's width / height
$rlBtnHover.RadiusX = 0.42; $rlBtnHover.RadiusY = 1.45
$rlButton.Background = $rlBtnBrush
function Set-RouletteGlow($e) {
    $p = $e.GetPosition($rlButton)
    $w = [Math]::Max(1.0, $rlButton.ActualWidth); $h = [Math]::Max(1.0, $rlButton.ActualHeight)
    $c = New-Object System.Windows.Point ([Math]::Min(1.0, [Math]::Max(0.0, $p.X / $w))), ([Math]::Min(1.0, [Math]::Max(0.0, $p.Y / $h)))
    $rlBtnHover.Center = $c; $rlBtnHover.GradientOrigin = $c
}
$rlBtnGrid = New-Object System.Windows.Controls.Grid
[void]$rlBtnGrid.Children.Add((New-RouletteFrame 3))
$rlBtnText = New-Object System.Windows.Controls.TextBlock
$rlBtnText.Text = 'SPIN'
$rlBtnText.FontFamily = $rlFont; $rlBtnText.FontWeight = 'Bold'; $rlBtnText.FontSize = 16 * $rlU
$rlBtnText.HorizontalAlignment = 'Center'; $rlBtnText.VerticalAlignment = 'Center'
$rlBtnText.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(226, 226, 226))
[void]$rlBtnGrid.Children.Add($rlBtnText)
$rlButton.Child = $rlBtnGrid
$rlButton.Add_MouseEnter({ param($s, $e) Set-RouletteGlow $e; $rlButton.Background = $rlBtnHover })
$rlButton.Add_MouseMove({ param($s, $e) Set-RouletteGlow $e })
$rlButton.Add_MouseLeave({ $rlButton.Background = $rlBtnBrush })
$rlButton.Add_MouseLeftButtonUp({ Start-PerkSpin })
$rlBtnWindow.Content = $rlButton

$rlSpinning = $false; $rlShown = $false; $rlHasResult = $false
$rlTickTimer = New-Object System.Windows.Threading.DispatcherTimer
$rlTickTimer.Interval = [TimeSpan]::FromMilliseconds(20)
$rlTickTimer.Add_Tick({
    $tick = $false
    foreach ($r in $rlReelsUi) {
        if ($r.Done) { continue }
        $idx = [int][Math]::Floor(($r.Start - $r.Move.Y) / $rlPitch + 0.5)
        if ($idx -ne $r.Index) { $r.Index = $idx; $tick = $true }
    }
    if ($tick) { Invoke-RouletteSound 'tick' }
})

# fades (the panel before the slide, the names after it)
function Show-RouletteFade($els, [int]$delayMs) {
    foreach ($el in @($els)) {
        $fade = New-Object System.Windows.Media.Animation.DoubleAnimation 0, 1, ([System.Windows.Duration][TimeSpan]::FromMilliseconds(300)); [void](Set-RouletteFps $fade)
        $fade.BeginTime = [TimeSpan]::FromMilliseconds($delayMs)
        $el.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fade)
    }
}
function Get-RouletteNames { @($rlReelsUi | ForEach-Object { $_.Name }) }
function Hide-RouletteList {
    foreach ($el in @($rlListPanel) + (Get-RouletteNames)) {
        $el.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null); $el.Opacity = 0
    }
}
function Reset-RouletteReelAnims($r) {
    foreach ($p in [System.Windows.Media.ScaleTransform]::ScaleXProperty, [System.Windows.Media.ScaleTransform]::ScaleYProperty) { $r.Scale.BeginAnimation($p, $null) }
    $r.Move.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $null)
    $r.RimBrush.BeginAnimation([System.Windows.Media.SolidColorBrush]::ColorProperty, $null)
    $r.RimBrush.Color = $rlRimCol
}
# the last result straight into its rows, no spin (loadout reopened before the match)
function Show-RouletteResult {
    for ($i = 0; $i -lt 4; $i++) {
        $r = $rlReelsUi[$i]
        Reset-RouletteReelAnims $r
        $r.Strip.Children.Clear(); [void]$r.Strip.Children.Add((New-RouletteIcon $r.Last))
        $r.Move.Y = ($rlD - $rlPitch) / 2
        $c = Get-RouletteRowCentre $i
        Set-ReelAt $r $c[0] $c[1] $rlRowScale
        $r.Done = $true; $r.Cell.Visibility = 'Visible'
    }
    Set-RouletteNames
    $rlListPanel.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null); $rlListPanel.Opacity = 1
    Show-RouletteFade (Get-RouletteNames) 0
}

# ---- The slide into the list: driven once per screen frame. Each frame just
# moves the 4 small reel windows and sets their size - nothing big redraws. ----
# Timing: the first frames after starting stall once (~35 ms, measured), so it
# holds still for 3 frames, and a slow frame never makes it jump - each frame
# advances by at most 2 frame-times.
# Motion (user, 2 Nov: "a bit smoother"): 650 ms per reel (was 480), a
# smootherstep curve (no sudden change of speed at either end) and each reel
# leaving 70 ms after the one before it, so they flow over as a wave.
$rlSlide = @{ On = $false; Last = $null; El = 0.0; Hold = 0; Ms = 650; Stagger = 70; Cap = 2000.0 / $rlFps; From = @(); To = @() }
$rlSlideTick = [EventHandler]{
    param($s, $e)
    $now = $e.RenderingTime
    if ($rlSlide.Last -ne $null -and $now -eq $rlSlide.Last) { return }   # same frame reported twice
    if ($rlSlide.Hold -lt 3) { $rlSlide.Hold++; $rlSlide.Last = $now; return }
    $rlSlide.El += [Math]::Min($rlSlide.Cap, ($now - $rlSlide.Last).TotalMilliseconds)
    $rlSlide.Last = $now
    for ($i = 0; $i -lt 4; $i++) {
        $t = ($rlSlide.El - $i * $rlSlide.Stagger) / $rlSlide.Ms
        if ($t -le 0) { continue }
        if ($t -gt 1) { if ($rlReelsUi[$i].S -eq $rlRowScale) { continue }; $t = 1.0 }
        $k = $t * $t * $t * ($t * (6 * $t - 15) + 10)   # smootherstep
        $a = $rlSlide.From[$i]; $b = $rlSlide.To[$i]
        Set-ReelAt $rlReelsUi[$i] ($a[0] + ($b[0] - $a[0]) * $k) ($a[1] + ($b[1] - $a[1]) * $k) (1 + ($rlRowScale - 1) * $k)
    }
    if ($rlSlide.El -ge $rlSlide.Ms + 3 * $rlSlide.Stagger) {
        Stop-RouletteSlide
        Set-RouletteNames
        Show-RouletteFade (Get-RouletteNames) 0
        $script:rlSpinning = $false; $script:rlHasResult = $true
        $rlButton.Opacity = 1
    }
}
function Stop-RouletteSlide {
    if ($rlSlide.On) { [System.Windows.Media.CompositionTarget]::remove_Rendering($rlSlideTick); $rlSlide.On = $false }
}
# after the last reel locks: the panel fades in during a short pause, then each
# diamond slides into its row
$rlListTimer = New-Object System.Windows.Threading.DispatcherTimer
$rlListTimer.Interval = [TimeSpan]::FromMilliseconds(650)
$rlListTimer.Add_Tick({
    $this.Stop()
    foreach ($r in $rlReelsUi) { Reset-RouletteReelAnims $r; $r.Move.Y = $r.Target }   # the pop / rim flash are over by now
    $rlSlide.From = @(0..3 | ForEach-Object { ,(Get-RouletteSlotCentre $_) })
    $rlSlide.To = @(0..3 | ForEach-Object { ,(Get-RouletteRowCentre $_) })
    $rlSlide.Last = $null; $rlSlide.El = 0.0; $rlSlide.Hold = 0; $rlSlide.On = $true
    [System.Windows.Media.CompositionTarget]::add_Rendering($rlSlideTick)
})

function New-RouletteIcon($perk) {
    $g = New-Object System.Windows.Controls.Grid
    $g.Width = $rlD; $g.Height = $rlPitch
    $img = New-Object System.Windows.Controls.Image
    $img.Width = $rlIcon; $img.Height = $rlIcon
    $img.HorizontalAlignment = 'Center'; $img.VerticalAlignment = 'Center'
    $img.Source = Get-RouletteIcon $perk.file
    [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($img, 'HighQuality')
    [void]$g.Children.Add($img)
    $g
}

# One handler for every reel (no closures - they can't reach this script's
# functions): whichever reel has reached its stop gets locked in
$rlOnReelDone = {
    foreach ($r in $rlReelsUi) {
        if ($r.Done -or $r.Move.Y -gt $r.Target + 0.5) { continue }
        $r.Done = $true
        Invoke-RouletteSound 'lock'
        $pop = New-Object System.Windows.Media.Animation.DoubleAnimation 1, 1.1, ([System.Windows.Duration][TimeSpan]::FromMilliseconds(90)); [void](Set-RouletteFps $pop)
        $pop.AutoReverse = $true
        $r.Scale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $pop)
        $r.Scale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $pop)
        $flash = New-Object System.Windows.Media.Animation.ColorAnimation $rlWhite, $rlRimCol, ([System.Windows.Duration][TimeSpan]::FromMilliseconds(450)); [void](Set-RouletteFps $flash)
        $r.RimBrush.BeginAnimation([System.Windows.Media.SolidColorBrush]::ColorProperty, $flash)
    }
    if (@($rlReelsUi | Where-Object { -not $_.Done }).Count -eq 0) {
        $rlTickTimer.Stop()
        Show-RouletteFade $rlListPanel 100
        $rlListTimer.Start()
    }
}

function Start-PerkSpin {
    if ($script:rlSpinning) { return }
    $pool = @($perkDb.perks)
    if ($pool.Count -lt 4) { return }
    $script:rlSpinning = $true; $script:rlHasResult = $false
    Stop-RouletteSlide
    $rlButton.Opacity = 0.55   # dimmed while spinning
    $rlListTimer.Stop()
    Hide-RouletteList
    $picks = @($pool | Get-Random -Count 4)   # 4 different perks
    $start = ($rlD - $rlPitch) / 2           # icons centred in the reel
    for ($i = 0; $i -lt 4; $i++) {
        $r = $rlReelsUi[$i]
        # back onto its slot, full size
        Reset-RouletteReelAnims $r
        $c = Get-RouletteSlotCentre $i
        Set-ReelAt $r $c[0] $c[1] 1.0
        $r.Cell.Visibility = 'Visible'
        $r.Done = $false; $r.Index = 0; $r.Start = $start
        $r.Strip.Children.Clear()
        # start on what this reel showed last time (no jump), a run of random
        # perks, the winner, and one spare below it
        $first = if ($r.Last) { $r.Last } else { $pool | Get-Random }
        [void]$r.Strip.Children.Add((New-RouletteIcon $first))
        for ($k = 1; $k -lt $rlStrip - 1; $k++) { [void]$r.Strip.Children.Add((New-RouletteIcon ($pool | Get-Random))) }
        [void]$r.Strip.Children.Add((New-RouletteIcon $picks[$i]))
        [void]$r.Strip.Children.Add((New-RouletteIcon ($pool | Get-Random)))
        $r.Last = $picks[$i]
        $r.Target = $start - ($rlStrip - 1) * $rlPitch
        $anim = New-Object System.Windows.Media.Animation.DoubleAnimation $start, $r.Target, ([System.Windows.Duration][TimeSpan]::FromSeconds($rlSpins[$i])); [void](Set-RouletteFps $anim)
        $ease = New-Object System.Windows.Media.Animation.QuarticEase
        $ease.EasingMode = 'EaseOut'
        $anim.EasingFunction = $ease
        $anim.Add_Completed($rlOnReelDone)
        $r.Move.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $anim)
    }
    $rlTickTimer.Start()
}

function Get-RouletteLayout {
    @{ BtnLeft = ($rlBtnCX - $rlBtnW / 2) * $rlU; BtnTop = ($rlBtnCY - $rlBtnH / 2) * $rlU }
}
function Set-RoulettePosition {
    $l = Get-RouletteLayout
    $rlBtnWindow.Left = $l.BtnLeft + $rlX0 + $rlOff; $rlBtnWindow.Top = $l.BtnTop + $rlY0
    $rlListWin.Left = $rlListAreaX * $rlU + $rlX0 + $rlOff; $rlListWin.Top = $rlListAreaY * $rlU + $rlY0
    foreach ($r in $rlReelsUi) { Set-ReelAt $r $r.CX $r.CY $r.S }
}

# Tests: everything the roulette shows, drawn into one picture of the 1080p
# area (290,200)-(1340,680), for pasting onto a loadout screenshot
function Save-RouletteRender([string]$path) {
    $ox = 290; $oy = 200
    $parts = @(@{ E = $rlListCanvas; X = $rlListAreaX; Y = $rlListAreaY; W = $rlListAreaW; H = $rlListAreaH })
    foreach ($r in $rlReelsUi) { $parts += @{ E = $r.Root; X = $r.CX - $rlHalf - $rlPad; Y = $r.CY - $rlHalf - $rlPad; W = $rlCellWin; H = $rlCellWin } }
    $dv = New-Object System.Windows.Media.DrawingVisual
    $dc = $dv.RenderOpen()
    foreach ($p in $parts) {
        $p.E.UpdateLayout()
        $vb = New-Object System.Windows.Media.VisualBrush $p.E
        $vb.ViewboxUnits = 'Absolute'; $vb.Viewbox = New-Object System.Windows.Rect 0, 0, ($p.W * $rlU), ($p.H * $rlU); $vb.Stretch = 'Fill'
        $dc.DrawRectangle($vb, $null, (New-Object System.Windows.Rect (($p.X - $ox) * $rlU), (($p.Y - $oy) * $rlU), ($p.W * $rlU), ($p.H * $rlU)))
    }
    $dc.Close()
    $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap ([int](1050 * $rlU)), ([int](480 * $rlU)), 96, 96, ([System.Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($dv)
    $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [IO.File]::Create($path); $enc.Save($fs); $fs.Close()
}

# Called by the overlay's 0.5 s timer: shows only while the loadout panel is on
# screen (and the game is in front); hidden elsewhere. The result is kept for
# the lobby and cleared once a match starts (map detected or match HUD seen).
function Update-Roulette {
    $inMatch = $sync.HaveMap -or ($sync.LastHud -and ((Get-Date) - $sync.LastHud).TotalSeconds -lt 10)
    if ($inMatch -and ($script:rlHasResult -or $rlReelsUi[0].Last)) {
        $script:rlHasResult = $false
        foreach ($r in $rlReelsUi) { $r.Last = $null }
    }
    # the latest screen read must show the loadout panel (reads come every ~2 s;
    # a stale "yes" from a stopped scanner doesn't count)
    $fresh = $sync.LastScan -and ((Get-Date) - $sync.LastScan).TotalSeconds -lt 4
    $show = $env:DBD_OVERLAY_SPIN -or ($sync.LoadoutNow -and $fresh -and $sync.DbdInFront)
    if ($show -and -not $script:rlShown) {
        $script:rlShown = $true
        # list first, so the reel windows stack above it
        $rlListWin.Show(); foreach ($r in $rlReelsUi) { $r.Win.Show() }; $rlBtnWindow.Show()
        Set-RoulettePosition
        if ($script:rlHasResult) { Show-RouletteResult }
    } elseif (-not $show -and $script:rlShown) {
        # left the loadout (even mid-spin): stop and put it away; a finished
        # result is kept for when the loadout opens again
        if ($script:rlSpinning) {
            $script:rlSpinning = $false
            $rlTickTimer.Stop(); $rlListTimer.Stop(); Stop-RouletteSlide
            foreach ($r in $rlReelsUi) { $r.Last = $null }   # an unfinished spin doesn't count
        }
        $script:rlShown = $false
        foreach ($r in $rlReelsUi) {
            $r.Move.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $null)
            $r.Done = $true; $r.Cell.Visibility = 'Hidden'
        }
        Hide-RouletteList
        $rlListWin.Hide(); foreach ($r in $rlReelsUi) { $r.Win.Hide() }; $rlBtnWindow.Hide()
        $rlButton.Opacity = 1
    }
}
