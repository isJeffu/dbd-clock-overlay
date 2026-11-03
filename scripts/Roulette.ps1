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
# The reel is exactly DbD's slot (half-diagonal 55 at 1080p) so its art - cut from
# the game, dbd-slot.png - shows at the game's own scale (user, 3 Nov: rim / purple
# didn't match when it was blown up to 72); the slot's tier pips show beside it.
$rlHalf  = 55
$rlShiftX = 0; $rlShiftY = 0
# Result list (1080p pixels): rows of diamond + name, sitting just ABOVE DbD's
# lobby chat box, centred on it (user, 3 Nov: "above the chat box like on top of
# it, not over"; "align by the middle") - it covers your character; close the
# loadout to see them. Chat box measured on the loadout at 1080p: x 1440-1779
# (not counting its minimise button), top 582.
$rlChatCX = (1440 + 1779) / 2; $rlChatY = 582
$rlChatGap  = 8                     # between the list and the chat box
$rlRowScale = 0.39 * 72 / 55        # result diamonds = 28 px half-diagonal (with the footer, the box keeps its old height)
$rlRowGap   = 6
$rlListPad  = 10
$rlNameW    = 160                   # room for the names (a padlock sits right of them)
$rlRowInset = 10                    # rows start this far further in: the diamonds stay clear of the box's frame line (user, 3 Nov)
$rlHeadH    = 24                    # header row: < ROLL 3/10 > (build history)
$rlFootH    = 18                    # footer: the equip reminder
$rlLockW    = 26                    # padlock column
$rlNameSize = 16                    # name text size
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
foreach ($pk in @($perkDb.perks) + @($perkDb.killerPerks)) { if ($pk) { $rlIconQueue.Enqueue($pk.file) } }
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
$rlUi = Get-DbdUi ([System.Windows.SystemParameters]::PrimaryScreenWidth) ([System.Windows.SystemParameters]::PrimaryScreenHeight) $(if ($state) { $state.UiLayout } else { 'auto' }) (Get-DbdScales).Menu   # DbD's Menu scale (read at start)
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
$rlFont      = New-Object System.Windows.Media.FontFamily ([Uri]((Join-Path $root 'assets\fonts') + '\')), './#Roboto, Segoe UI'
$rlFrameCol  = [System.Windows.Media.Color]::FromRgb(153, 154, 155)   # the worn grey line inside DbD's boxes (sampled off the SEARCH box at 4K)
# DbD's boxes (SEARCH, BACK): torn black edge, a worn grey line, marble-like
# cracks (user, 3 Nov: "more like marble" - use the real thing). The texture is
# the game's own SEARCH box, cut from a 4K screenshot by dev\make-box-texture.ps1
# (Behaviour's art, used under its fan-content guidelines - see README), drawn
# as a 9-slice: corners at their real size, edges and middle tiled. Without the
# file: a plain grey line inside the black box.
$rlBoxTex = $null
try {
    $bp = Join-Path $root 'assets\textures\dbd-box.png'
    if (Test-Path $bp) {
        $rlBoxTex = New-Object System.Windows.Media.Imaging.BitmapImage
        $rlBoxTex.BeginInit(); $rlBoxTex.UriSource = New-Object System.Uri $bp; $rlBoxTex.CacheOption = 'OnLoad'; $rlBoxTex.EndInit(); $rlBoxTex.Freeze()
    }
} catch { $rlBoxTex = $null }
$rlBoxCut = @{ L = 30; R = 30; T = 26; B = 26 }   # 9-slice cuts in texture px (4K: 2 px per 1080p px)
# soft light under the mouse on SPIN / THEME (over the texture, under the text)
$rlBtnGlow = New-Object System.Windows.Media.RadialGradientBrush
$rlBtnGlow.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.Color]::FromArgb(95, 200, 200, 205)), 0))
$rlBtnGlow.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.Color]::FromArgb(30, 200, 200, 205)), 0.55))
$rlBtnGlow.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.Color]::FromArgb(0, 200, 200, 205)), 1))
$rlBtnGlow.RadiusX = 0.42; $rlBtnGlow.RadiusY = 1.45
# $scale: the frame drawn smaller with a smaller box (1 = the real SEARCH box, 55 px tall),
# so it keeps DbD's proportions at any size
function New-RouletteFrame([double]$inset, [double]$scale = 1) {
    $g = New-Object System.Windows.Controls.Grid
    $g.IsHitTestVisible = $false
    if ($rlBoxTex) {
        $tw = $rlBoxTex.PixelWidth; $th = $rlBoxTex.PixelHeight; $k = $rlU / 2 * $scale   # texture px -> WPF units
        $cols = @(@{ X = 0; W = $rlBoxCut.L }, @{ X = $rlBoxCut.L; W = $tw - $rlBoxCut.L - $rlBoxCut.R }, @{ X = $tw - $rlBoxCut.R; W = $rlBoxCut.R })
        $rows = @(@{ Y = 0; H = $rlBoxCut.T }, @{ Y = $rlBoxCut.T; H = $th - $rlBoxCut.T - $rlBoxCut.B }, @{ Y = $th - $rlBoxCut.B; H = $rlBoxCut.B })
        foreach ($c in 0..2) {   # fixed / stretching / fixed
            $cd = New-Object System.Windows.Controls.ColumnDefinition
            $cd.Width = if ($c -eq 1) { New-Object System.Windows.GridLength 1, 'Star' } else { New-Object System.Windows.GridLength ($cols[$c].W * $k) }
            $g.ColumnDefinitions.Add($cd)
            $rd = New-Object System.Windows.Controls.RowDefinition
            $rd.Height = if ($c -eq 1) { New-Object System.Windows.GridLength 1, 'Star' } else { New-Object System.Windows.GridLength ($rows[$c].H * $k) }
            $g.RowDefinitions.Add($rd)
        }
        for ($r = 0; $r -lt 3; $r++) { for ($c = 0; $c -lt 3; $c++) {
            $b = New-Object System.Windows.Media.ImageBrush $rlBoxTex
            $b.ViewboxUnits = 'Absolute'; $b.Viewbox = New-Object System.Windows.Rect $cols[$c].X, $rows[$r].Y, $cols[$c].W, $rows[$r].H
            $b.Stretch = 'Fill'
            if ($r -eq 1 -or $c -eq 1) {   # edges + middle repeat at the texture's own scale
                $b.TileMode = 'Tile'; $b.ViewportUnits = 'Absolute'
                $b.Viewport = New-Object System.Windows.Rect 0, 0, ($cols[$c].W * $k), ($rows[$r].H * $k)
            }
            $b.Freeze()
            $p = New-Object System.Windows.Shapes.Rectangle; $p.Fill = $b; $p.SnapsToDevicePixels = $true
            [System.Windows.Controls.Grid]::SetRow($p, $r); [System.Windows.Controls.Grid]::SetColumn($p, $c)
            [void]$g.Children.Add($p)
        } }
    } else {
        $f = New-Object System.Windows.Shapes.Rectangle
        $f.Stroke = New-Object System.Windows.Media.SolidColorBrush $rlFrameCol
        $f.StrokeThickness = 2 * $rlU
        $f.Margin = New-Object System.Windows.Thickness ($inset * $rlU)
        [void]$g.Children.Add($f)
    }
    # hover light (SPIN / THEME switch its Fill on and off; .Tag points at it)
    $glow = New-Object System.Windows.Shapes.Rectangle
    $glow.Margin = New-Object System.Windows.Thickness (4 * $rlU)
    [System.Windows.Controls.Grid]::SetRowSpan($glow, 3); [System.Windows.Controls.Grid]::SetColumnSpan($glow, 3)
    [void]$g.Children.Add($glow); $g.Tag = $glow
    $g
}
# with the texture the boxes are the texture itself: no extra fill or edge
function Set-RouletteBoxLook($border, $fill) {
    if ($rlBoxTex) { $border.Background = [System.Windows.Media.Brushes]::Transparent; $border.BorderThickness = 0 }
    else { $border.Background = $fill }
}
# ---- Result list geometry (1080p pixels) ----
$rlRowHalf = $rlHalf * $rlRowScale                    # half-diagonal of a result diamond
$rlRowH    = 2 * $rlRowHalf + $rlRowGap
$rlListH   = $rlHeadH + 4 * $rlRowH - $rlRowGap + $rlFootH + 2 * $rlListPad
$rlListW   = $rlListPad + $rlRowInset + 2 * $rlRowHalf + 14 + $rlNameW + $rlLockW + $rlListPad
# The chat box is pinned to the screen's RIGHT and BOTTOM (the slots, and all the
# design pixels here, to the left / top): this shift puts it there on ultrawide
# screens and when DbD's Menu scale shrinks the UI towards its corners. 0 on
# 16:9 at 100%.
$rlListDX  = ($rlUi.Right - $rlUi.Left) / $rlU - 1920
$rlListDY  = 1080 / (Get-DbdScales).Menu - 1080   # (the 16:9 area's bottom is 1080 unscaled design px down)
$rlListX   = $rlChatCX - $rlListW / 2 + $rlListDX
$rlListY   = $rlChatY - $rlChatGap - $rlListH + $rlListDY
function Get-RouletteRowCentre([int]$i) { @(($rlListX + $rlListPad + $rlRowInset + $rlRowHalf), ($rlListY + $rlListPad + $rlHeadH + $rlRowHalf + $i * $rlRowH)) }
function Get-RouletteSlotCentre([int]$i) { @(($rlSlotX[$i] + $rlShiftX), ($rlSlotY + $rlShiftY)) }

# ---- Windows. A see-through window is redrawn whole every frame, so nothing
# moving lives in a big one (the old shared reel window covered slots + list
# during the slide and lagged - user, 2 Nov). Each reel has its own small
# window that is MOVED during the slide; the list panel + names sit in a
# window of their own that only redraws while fading. All click-through. ----
# The list window covers this area (1080p pixels):
$rlListAreaX = $rlListX - 6; $rlListAreaY = $rlListY - 6; $rlListAreaW = $rlListW + 12; $rlListAreaH = $rlListH + 12
$rlListWin = New-OverlayWindow 'DbD Clock Overlay roulette list'
$rlListWin.SizeToContent = 'Manual'
$rlListWin.Width = $rlListAreaW * $rlU; $rlListWin.Height = $rlListAreaH * $rlU
$rlListCanvas = New-Object System.Windows.Controls.Canvas
$rlListCanvas.Width = $rlListAreaW * $rlU; $rlListCanvas.Height = $rlListAreaH * $rlU
$rlListWin.Content = $rlListCanvas

$rlListPanel = New-Object System.Windows.Controls.Border
Set-RouletteBoxLook $rlListPanel (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(215, 8, 8, 9)))
$rlListPanel.Child = New-RouletteFrame 4
$rlListPanel.Width = $rlListW * $rlU; $rlListPanel.Height = $rlListH * $rlU
[System.Windows.Controls.Canvas]::SetLeft($rlListPanel, ($rlListX - $rlListAreaX) * $rlU)
[System.Windows.Controls.Canvas]::SetTop($rlListPanel, ($rlListY - $rlListAreaY) * $rlU)
$rlListPanel.Opacity = 0
[void]$rlListCanvas.Children.Add($rlListPanel)

# The panel takes clicks (padlocks, history arrows) but, like SPIN, never takes
# focus from the game; its see-through parts still let clicks through to DbD
$rlListWin.Add_SourceInitialized({
    param($s, $e)
    $h = (New-Object System.Windows.Interop.WindowInteropHelper $s).Handle
    [void][OverlayNative]::SetWindowLong($h, -20, ([OverlayNative]::GetWindowLong($h, -20) -band (-bnot 0x20)))   # not click-through
})
$rlGlyphs = New-Object System.Windows.Media.FontFamily 'Segoe MDL2 Assets, Segoe UI Symbol'
function New-RouletteText([string]$text, [double]$size, $font, [byte]$grey) {
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $text; $t.FontFamily = $font; $t.FontSize = $size * $rlU; $t.FontWeight = 'Bold'
    $t.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb($grey, $grey, $grey))
    $t.Background = [System.Windows.Media.Brushes]::Transparent   # the whole box is clickable, not just the strokes
    $t.Opacity = 0
    [void]$rlListCanvas.Children.Add($t); $t
}
# header: < ROLL 3/10 > (build history, newest first)
$rlHistPrev = New-RouletteText ([string][char]0xE76B) 13 $rlGlyphs 200
$rlHistText = New-RouletteText '' 13 $rlFont 170
$rlHistNext = New-RouletteText ([string][char]0xE76C) 13 $rlGlyphs 200
foreach ($b in $rlHistPrev, $rlHistNext) { $b.Cursor = [System.Windows.Input.Cursors]::Hand; $b.Padding = New-Object System.Windows.Thickness (6 * $rlU), (2 * $rlU), (6 * $rlU), (2 * $rlU) }
$rlHistPrev.Add_MouseLeftButtonUp({ Show-RouletteHistory ($script:rlHistIdx + 1) })   # older
$rlHistNext.Add_MouseLeftButtonUp({ if ($script:rlHistIdx -gt 1) { Show-RouletteHistory ($script:rlHistIdx - 1) } })   # newer (the current roll is the clock's job)
# clock: past rolls on / off (user, 3 Nov: only the CURRENT roll can be re-rolled
# or locked; the last 10 are just to look at, behind a history button)
$rlHistBtn = New-RouletteText ([string][char]0xE81C) 13 $rlGlyphs 150
$rlHistBtn.Cursor = [System.Windows.Input.Cursors]::Hand
$rlHistBtn.Padding = New-Object System.Windows.Thickness (5 * $rlU), (2 * $rlU), (5 * $rlU), (2 * $rlU)
$rlHistBtn.Add_MouseLeftButtonUp({ Switch-RouletteHistoryView })
# bin left of ">": clears this side's history (user, 3 Nov) - the first click
# asks, a second within 3 s clears; the roll on screen stays
$rlHistClear = New-RouletteText ([string][char]0xE74D) 12 $rlGlyphs 150
$rlHistClear.Cursor = [System.Windows.Input.Cursors]::Hand
$rlHistClear.Padding = New-Object System.Windows.Thickness (5 * $rlU), (2 * $rlU), (5 * $rlU), (2 * $rlU)
$rlHistClear.Add_MouseLeftButtonUp({ Clear-RouletteHistory })
$rlClearArmed = $false
# footer: the roulette only SHOWS a build (user, 3 Nov: "a reminder to actually
# change your perks" - at the bottom of the results box)
$rlEquipNote = New-RouletteText 'REMEMBER TO EQUIP THESE PERKS' 11 $rlFont 175
$rlClearTimer = New-Object System.Windows.Threading.DispatcherTimer
$rlClearTimer.Interval = [TimeSpan]::FromSeconds(3)
$rlClearTimer.Add_Tick({ $this.Stop(); $script:rlClearArmed = $false; Set-RouletteNames })
# one padlock per row: locked = that perk stays when you SPIN again
$rlPadlocks = @(0..3 | ForEach-Object {
    $p = New-RouletteText ([string][char]0xE785) 15 $rlGlyphs 110
    $p.Cursor = [System.Windows.Input.Cursors]::Hand; $p.Tag = $_
    $p.Padding = New-Object System.Windows.Thickness (4 * $rlU)
    $p.Add_MouseLeftButtonUp({ param($s, $e) Switch-RouletteLock ([int]$s.Tag) })
    $p
})

# ---- Build history: the last 10 rolls per side, kept in roulette-history.json ----
$rlHistPath = Join-Path $root 'roulette-history.json'
$rlHistory = New-Object System.Collections.ArrayList
# (no @() round ConvertFrom-Json: in PowerShell 5.1 that makes the whole array ONE item)
try { if (Test-Path $rlHistPath) { $saved = Get-Content $rlHistPath -Raw -Encoding UTF8 | ConvertFrom-Json; foreach ($h in $saved) { [void]$rlHistory.Add(@{ Role = [string]$h.Role; Names = @($h.Names); Char = [string]$h.Char }) } } } catch {}
$rlHistIdx = 0
# roulette-debug.flag (set in ClockOverlay.ps1): a line per event, with the screen-read state
function Write-RouletteLog([string]$what) {
    if (-not $script:rlDebug) { return }
    try { Add-Content (Join-Path $root 'roulette-debug.txt') ('{0:HH:mm:ss.fff} {1}' -f (Get-Date), $what) } catch {}
}
function Get-RouletteHistory { @($rlHistory | Where-Object { $_.Role -eq $script:rlRole }) }
function Add-RouletteHistory {
    $names = @($rlReelsUi | ForEach-Object { $_.Last.name })
    $char = @($rlReelsUi | Where-Object { $_.Last.Empty } | ForEach-Object { $_.Last.character }) | Select-Object -First 1   # an Adept roll's character
    $rlHistory.Insert(0, @{ Role = $script:rlRole; Names = $names; Char = [string]$char })
    # keep 10 per side
    $keep = New-Object System.Collections.ArrayList; $count = @{}
    foreach ($h in $rlHistory) { $count[$h.Role] = 1 + [int]$count[$h.Role]; if ($count[$h.Role] -le 10) { [void]$keep.Add($h) } }
    $script:rlHistory = $keep; $script:rlHistIdx = 0
    Save-RouletteHistory
}
function Save-RouletteHistory {
    try { [IO.File]::WriteAllText($rlHistPath, (ConvertTo-Json @($rlHistory | ForEach-Object { [pscustomobject]$_ }) -Depth 4), (New-Object Text.UTF8Encoding $false)) } catch {}
}
# show an older / newer roll (no spin); locks are cleared - they belonged to the shown roll
function Switch-RouletteHistoryView {
    if ($script:rlSpinning -or (Test-RouletteFilling)) { return }
    if ($script:rlHistIdx -gt 0) { Show-RouletteHistory 0 }               # back to the current roll
    elseif (@(Get-RouletteHistory).Count -gt 1) { Show-RouletteHistory 1 } # the roll before it
}
$rlCurLocks = @($false, $false, $false, $false)   # the current roll's padlocks while looking at past ones
function Show-RouletteHistory([int]$idx) {
    if ($script:rlSpinning -or (Test-RouletteFilling) -or $rlSlide.On) { return }
    $list = @(Get-RouletteHistory)
    if ($idx -lt 0 -or $idx -ge $list.Count) { return }
    $pool = if ($script:rlRole -eq 'killer') { @($perkDb.killerPerks) } else { @($perkDb.perks) }
    $perks = @($list[$idx].Names | ForEach-Object { $n = $_; if (-not $n) { New-RouletteEmpty $list[$idx].Char } else { $pool | Where-Object { $_.name -eq $n } | Select-Object -First 1 } })
    if ($perks.Count -ne 4 -or @($perks | Where-Object { -not $_ }).Count) { return }   # a perk that's gone from the list
    if ($script:rlHistIdx -eq 0 -and $idx -gt 0) { $script:rlCurLocks = @($rlReelsUi | ForEach-Object { [bool]$_.Locked }) }   # leaving the current roll
    $script:rlHistIdx = $idx
    for ($i = 0; $i -lt 4; $i++) { $rlReelsUi[$i].Last = $perks[$i]; $rlReelsUi[$i].Locked = ($idx -eq 0 -and $script:rlCurLocks[$i]) }
    $script:rlHasResult = $true
    Show-RouletteResult
}
function Clear-RouletteHistory {
    if ($script:rlSpinning) { return }
    if (-not $script:rlClearArmed) {
        $script:rlClearArmed = $true; $rlClearTimer.Stop(); $rlClearTimer.Start()
        Set-RouletteNames; return
    }
    $rlClearTimer.Stop(); $script:rlClearArmed = $false
    if ($script:rlHistIdx -gt 0) { Show-RouletteHistory 0 }   # back on the current roll first: it's the one that stays
    $keep = New-Object System.Collections.ArrayList
    foreach ($h in $rlHistory) { if ($h.Role -ne $script:rlRole) { [void]$keep.Add($h) } }
    $script:rlHistory = $keep; $script:rlHistIdx = 0
    Save-RouletteHistory
    Set-RouletteNames
}
function Switch-RouletteLock([int]$i) {
    if ($script:rlSpinning -or (Test-RouletteFilling) -or -not $rlReelsUi[$i].Last -or $script:rlHistIdx -gt 0) { return }
    if ($rlReelsUi[$i].Last.Empty) { Add-RoulettePerkToSlot $i; return }   # the "+" on an empty Adept slot
    $rlReelsUi[$i].Locked = -not $rlReelsUi[$i].Locked
    Set-RouletteNames
}
# Adept leaves the last slot empty (the achievement is done with only the
# character's 3 perks) - but it's only a default: the row asks "WANT A 4TH PERK?"
# (user, 3 Nov) and a click spins that one slot, right there in the list.
# Clicking any unlocked perk's name re-rolls it the same way (user, 3 Nov: never
# a perk already in the box; several can spin at once).
function New-RouletteEmpty([string]$char) { [pscustomobject]@{ name = ''; file = $null; character = $char; tags = @(); Empty = $true } }
function Test-RouletteFilling { @($rlReelsUi | Where-Object { $_.Filling }).Count -gt 0 }
# what a re-roll draws from: the theme still applies (a SLOWDOWN perk becomes
# another SLOWDOWN perk; EXHAUSTION keeps exactly one exhaustion perk)
function Get-RouletteRerollPool($old) {
    $pool = if ($script:rlRole -eq 'killer') { @($perkDb.killerPerks) } else { @($perkDb.perks) }
    $taken = @($rlReelsUi | ForEach-Object { $_.Last.name })
    $free = @($pool | Where-Object { $_.name -notin $taken })
    $theme = (Get-RouletteTheme).K
    $want = switch ($theme) {
        'exhaustion' {
            $others = @($rlReelsUi | Where-Object { $_.Last -ne $old -and $_.Last.tags -contains 'exhaustion' }).Count
            if ($others) { @($free | Where-Object { $_.tags -notcontains 'exhaustion' }) } else { @($free | Where-Object { $_.tags -contains 'exhaustion' }) }
        }
        { $_ -in 'any', 'char' } { $free }
        default { if ($old.tags -contains $theme) { @($free | Where-Object { $_.tags -contains $theme }) } else { $free } }
    }
    if (@($want).Count) { @($want) } else { $free }   # a theme with nothing left: any perk
}
function Add-RoulettePerkToSlot([int]$i) {
    Write-RouletteLog "re-roll row $i"
    $r = $rlReelsUi[$i]
    if ($script:rlSpinning -or $r.Filling -or $r.Locked -or -not $r.Last -or $script:rlHistIdx -gt 0) { return }   # a past roll is view-only
    Hide-RouletteTip
    $from = Get-RouletteRerollPool $r.Last
    if (-not $from.Count) { return }
    $p = $from | Get-Random
    $pool = if ($script:rlRole -eq 'killer') { @($perkDb.killerPerks) } else { @($perkDb.perks) }
    $old = $r.Last; $r.Last = $p   # set now, so a second re-roll can't pick it too
    # the roll shown is a history entry: keep it in step
    $h = @(Get-RouletteHistory)[$script:rlHistIdx]
    if ($h) { $h.Names = @($rlReelsUi | ForEach-Object { $_.Last.name }); Save-RouletteHistory }
    # a short spin of this reel (what it showed, a run of random perks, the winner, a spare)
    $r.Filling = $true; Set-ReelRolling $r $true
    $start = ($rlD - $rlPitch) / 2; $n = 14
    $r.Strip.Children.Clear(); [void]$r.Strip.Children.Add((New-RouletteIcon $old))
    for ($k = 1; $k -lt $n - 1; $k++) { [void]$r.Strip.Children.Add((New-RouletteIcon ($pool | Get-Random))) }
    [void]$r.Strip.Children.Add((New-RouletteIcon $p)); [void]$r.Strip.Children.Add((New-RouletteIcon ($pool | Get-Random)))
    $r.Done = $false; $r.Index = 0; $r.Start = $start; $r.Target = $start - ($n - 1) * $rlPitch
    $anim = New-Object System.Windows.Media.Animation.DoubleAnimation $start, $r.Target, ([System.Windows.Duration][TimeSpan]::FromSeconds(1.4)); [void](Set-RouletteFps $anim)
    $ease = New-Object System.Windows.Media.Animation.QuarticEase; $ease.EasingMode = 'EaseOut'; $anim.EasingFunction = $ease
    $anim.Add_Completed($rlOnFillDone)
    $r.Move.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $anim)
    $rlTickTimer.Start()
    $r.Name.Text = ''   # the name appears when it lands
}
# a re-rolled slot landed: clunk + rim flash, then its name
$rlOnFillDone = {
    foreach ($r in $rlReelsUi) {
        if (-not $r.Filling -or $r.Move.Y -gt $r.Target + 0.5) { continue }   # (left the loadout meanwhile: Filling is off)
        $r.Filling = $false; $r.Done = $true; Set-ReelRolling $r $false   # landed: icon on top of the rim
        Invoke-RouletteSound 'lock'
        $flash = New-Object System.Windows.Media.Animation.ColorAnimation $rlWhite, $rlRimCol, ([System.Windows.Duration][TimeSpan]::FromMilliseconds(450)); [void](Set-RouletteFps $flash)
        $r.RimBrush.BeginAnimation([System.Windows.Media.SolidColorBrush]::ColorProperty, $flash)
    }
    if (-not (Test-RouletteFilling) -and -not $script:rlSpinning) { $rlTickTimer.Stop() }
    Set-RouletteNames
}

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
# Slot purple: the game's own "very rare" background (the one behind tier III
# perks), downloaded from the DbD wiki with the perk icons (Setup.ps1) - user,
# 3 Nov: use the real thing. Our hand-made assets\textures\perk-slot.png if it
# isn't there yet.
$rlSlotTex = $null; $rlSlotReal = $false
try {
    foreach ($texPath in (Join-Path $root 'icons\Dbd-veryrare-enhanced.png'), (Join-Path $root 'assets\textures\perk-slot.png')) {
        if (-not (Test-Path $texPath)) { continue }
        $rlSlotReal = $texPath -like '*veryrare*'
        $rlSlotTex = New-Object System.Windows.Media.Imaging.BitmapImage
        $rlSlotTex.BeginInit(); $rlSlotTex.CacheOption = 'OnLoad'
        if ($rlSlotReal) {
            # the game draws it lighter than the wiki file: average RGB 63,30,76 on the
            # wiki vs 99,71,110 on a 4K loadout (measured 3 Nov) - lift it to match
            $src = [System.Drawing.Image]::FromFile($texPath)
            $adj = New-Object System.Drawing.Bitmap $src.Width, $src.Height
            $cm = New-Object System.Drawing.Imaging.ColorMatrix
            $cm.Matrix00 = 1.2; $cm.Matrix11 = 1.3; $cm.Matrix22 = 1.15
            $cm.Matrix40 = 23 / 255; $cm.Matrix41 = 32 / 255; $cm.Matrix42 = 23 / 255
            $ia = New-Object System.Drawing.Imaging.ImageAttributes; $ia.SetColorMatrix($cm)
            $gg = [System.Drawing.Graphics]::FromImage($adj)
            $gg.DrawImage($src, (New-Object System.Drawing.Rectangle 0, 0, $src.Width, $src.Height), 0, 0, $src.Width, $src.Height, 'Pixel', $ia)
            $gg.Dispose(); $src.Dispose()
            $ms = New-Object System.IO.MemoryStream; $adj.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png); $adj.Dispose(); $ms.Position = 0
            $rlSlotTex.StreamSource = $ms
        } else { $rlSlotTex.UriSource = New-Object System.Uri $texPath }
        $rlSlotTex.EndInit(); $rlSlotTex.Freeze()
        break
    }
} catch { $rlSlotTex = $null }
# Best of all: DbD's own perk slot, purple AND black rim, cut from a 4K loadout
# screenshot by dev\make-slot-from-shot.ps1 (user, 3 Nov: the rim / purple didn't
# look like Behaviour's). It's the whole diamond, tip to tip.
$rlSlotFull = $null
try {
    $sp = Join-Path $root 'assets\textures\dbd-slot.png'
    if (Test-Path $sp) {
        $rlSlotFull = New-Object System.Windows.Media.Imaging.BitmapImage
        $rlSlotFull.BeginInit(); $rlSlotFull.UriSource = New-Object System.Uri $sp; $rlSlotFull.CacheOption = 'OnLoad'; $rlSlotFull.EndInit(); $rlSlotFull.Freeze()
    }
} catch { $rlSlotFull = $null }
$rlPips = $null
try {
    $pp = Join-Path $root 'assets\textures\dbd-pips.png'
    if ($rlSlotFull -and (Test-Path $pp)) {
        $rlPips = New-Object System.Windows.Media.Imaging.BitmapImage
        $rlPips.BeginInit(); $rlPips.UriSource = New-Object System.Uri $pp; $rlPips.CacheOption = 'OnLoad'; $rlPips.EndInit(); $rlPips.Freeze()
    }
} catch { $rlPips = $null }
# rim: the grungy black of DbD's own boxes (dbd-box.png's middle); the white
# lock flash is then a layer of its own on top, clear when not flashing
$rlRimTex = $null
if ($rlSlotFull) { $rlRimCol = [System.Windows.Media.Color]::FromArgb(0, 240, 240, 240) }   # the slot image has its rim
elseif ($rlBoxTex) {
    $rlRimTex = New-Object System.Windows.Media.ImageBrush $rlBoxTex
    $rlRimTex.ViewboxUnits = 'Absolute'; $rlRimTex.Viewbox = New-Object System.Windows.Rect 40, 34, 150, 52
    $rlRimTex.TileMode = 'Tile'; $rlRimTex.ViewportUnits = 'Absolute'; $rlRimTex.Viewport = New-Object System.Windows.Rect 0, 0, (75 * $rlU), (26 * $rlU)
    $rlRimTex.Freeze()
    $rlRimCol = [System.Windows.Media.Color]::FromArgb(0, 240, 240, 240)   # the flash fades out to nothing
}
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
    # purple slot: the game's grungy purple, turned differently per reel so the
    # four don't look identical; plain gradient if no texture
    $bg = New-Object System.Windows.Shapes.Path
    $bg.Data = New-DiamondGeometry $rlD 0
    if ($rlSlotFull) {
        # the real slot, rim and all, turned per reel so the four don't look identical
        $tb = New-Object System.Windows.Media.ImageBrush $rlSlotFull
        $tb.RelativeTransform = New-Object System.Windows.Media.RotateTransform (90 * $i), 0.5, 0.5
        $tb.Freeze(); $bg.Fill = $tb
    } elseif ($rlSlotReal) {
        # the wiki's square: inside its dark border, turned 45 degrees and shrunk so
        # its edges ARE the diamond's (as the game draws it)
        $tb = New-Object System.Windows.Media.ImageBrush $rlSlotTex
        $tb.Viewbox = New-Object System.Windows.Rect 0.1, 0.1, 0.8, 0.8
        $tg = New-Object System.Windows.Media.TransformGroup
        $tg.Children.Add((New-Object System.Windows.Media.ScaleTransform 0.7072, 0.7072, 0.5, 0.5))
        $tg.Children.Add((New-Object System.Windows.Media.RotateTransform (45 + 90 * $i), 0.5, 0.5))
        $tb.RelativeTransform = $tg
        $tb.Freeze(); $bg.Fill = $tb
    } elseif ($rlSlotTex) {
        $tb = New-Object System.Windows.Media.ImageBrush $rlSlotTex
        $fx = if ($i % 2) { -1.0 } else { 1.0 }; $fy = if ($i -ge 2) { -1.0 } else { 1.0 }
        $tb.RelativeTransform = New-Object System.Windows.Media.ScaleTransform $fx, $fy, 0.5, 0.5
        $tb.Freeze(); $bg.Fill = $tb
    } else { $bg.Fill = New-Object System.Windows.Media.LinearGradientBrush $rlPurpleTop, $rlPurpleBot, 90 }
    [void]$cell.Children.Add($bg)
    # the rolling strip, clipped to the diamond
    $win = New-Object System.Windows.Controls.Canvas
    $win.Width = $rlD; $win.Height = $rlD
    $win.Clip = New-DiamondGeometry $rlD 0   # while rolling: cut at the slot's outer edge, over its rim
    $strip = New-Object System.Windows.Controls.StackPanel
    $move = New-Object System.Windows.Media.TranslateTransform 0, 0
    $strip.RenderTransform = $move
    [void]$win.Children.Add($strip)
    [void]$cell.Children.Add($win)
    $ring = $null   # (icons spin and land ON TOP of the rim, as in the game - user, 3 Nov)
    # thick black rim; flashes white as the reel locks (the game's "selected" look)
    # game's rim: 6.4 px on a bare slot (half-diagonal 55, 1080p), scaled to the reel like the icons
    $rimW = 6.4 * ($rlHalf / 55.0)
    if ($rlRimTex) {   # the textured black, under the flash layer
        $rimT = New-Object System.Windows.Shapes.Path
        $rimT.Data = New-DiamondGeometry $rlD ($rimW / 2 * $rlU)
        $rimT.Stroke = $rlRimTex; $rimT.StrokeThickness = $rimW * $rlU; $rimT.StrokeLineJoin = 'Miter'
        [void]$cell.Children.Add($rimT)
    }
    $rimBrush = New-Object System.Windows.Media.SolidColorBrush $rlRimCol
    $rim = New-Object System.Windows.Shapes.Path
    $rim.Data = New-DiamondGeometry $rlD ($rimW / 2 * $rlU)
    $rim.Stroke = $rimBrush
    $rim.StrokeThickness = $rimW * $rlU; $rim.StrokeLineJoin = 'Miter'
    [void]$cell.Children.Add($rim)
    # its own three tier pips (tier III, like the purple), cut from the game's
    # loadout (dbd-pips.png), exactly where the slot's are - covers the equipped
    # perk's pips underneath (user, 3 Nov)
    if ($rlPips) {
        $pi = New-Object System.Windows.Controls.Image
        $pi.Source = $rlPips; $pi.Width = 30 * $rlU; $pi.Height = 39 * $rlU; $pi.Stretch = 'Fill'
        [System.Windows.Controls.Canvas]::SetLeft($pi, $rlD / 2 + 13 * $rlU); [System.Windows.Controls.Canvas]::SetTop($pi, $rlD / 2 - 52 * $rlU)   # (+26,-104 px at 4K from the centre)
        [void]$cell.Children.Add($pi)
    }
    $cell.Visibility = 'Hidden'
    [void]$root2.Children.Add($cell)
    # its name, beside its row in the list (in the list window)
    $name = New-Object System.Windows.Controls.TextBlock
    $name.FontFamily = $rlFont; $name.FontWeight = 'Bold'; $name.FontSize = $rlNameSize * $rlU
    $name.Foreground = New-Object System.Windows.Media.SolidColorBrush $rlWhite
    $name.Width = $rlNameW * $rlU; $name.TextWrapping = 'Wrap'
    $name.Opacity = 0
    # the name is a button: re-rolls that perk, or fills an empty Adept slot
    $name.Background = [System.Windows.Media.Brushes]::Transparent; $name.Tag = $i
    $name.Add_MouseLeftButtonUp({ param($s, $e) Add-RoulettePerkToSlot ([int]$s.Tag) })   # re-roll this one (or fill an empty Adept slot)
    [void]$rlListCanvas.Children.Add($name)
    $slotC = Get-RouletteSlotCentre $i
    $rlReelsUi += @{ Win = $reelWin; Root = $root2; Cell = $cell; Scale = $scale; Strip = $strip; Move = $move; RimBrush = $rimBrush; Name = $name
                     Last = $null; Locked = $false; Filling = $false; Shadow = $sh; Ring = $ring; Clipper = $win; ClipGeo = $win.Clip; Index = 0; Done = $true; Target = 0; CX = $slotC[0]; CY = $slotC[1]; S = 1.0; Hwnd = [IntPtr]::Zero; PX = $null; PY = $null }
}

# Put a reel's window so the diamond's centre is at (cx, cy) in 1080p pixels,
# at the given size. Once the window is up it's moved with one SetWindowPos
# (setting Left then Top would move it twice per frame).
$rlDpi = 0
function Set-ReelAt($r, [double]$cx, [double]$cy, [double]$s) {
    $r.CX = $cx; $r.CY = $cy; $r.S = $s
    $r.Scale.ScaleX = $s; $r.Scale.ScaleY = $s
    # the drop shadow is for the grey loadout: it fades out on the way into the results
    # box, whose black made it a solid dark diamond (user, 3 Nov)
    $o = [Math]::Max(0, [Math]::Min(1, ($s - $rlRowScale) / (1 - $rlRowScale)))
    if ($r.Shadow.Opacity -ne $o) { $r.Shadow.Opacity = $o }
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
        $r.Name.Text = if ($r.Filling) { '' } elseif ($r.Last.Empty) { 'WANT A 4TH PERK?' } elseif ($r.Last) { $r.Last.name.ToUpper() } else { '' }
        $r.Name.Foreground = New-Object System.Windows.Media.SolidColorBrush $(if ($r.Last.Empty) { [System.Windows.Media.Color]::FromRgb(170, 170, 170) } else { $rlWhite })
        $r.Name.Cursor = if ($r.Last -and -not $r.Locked -and $script:rlHistIdx -eq 0) { [System.Windows.Input.Cursors]::Hand } else { $null }   # click = re-roll / fill (current roll only)
        $r.Name.Measure([System.Windows.Size]::new($r.Name.Width, [double]::PositiveInfinity))
        [System.Windows.Controls.Canvas]::SetLeft($r.Name, ($c[0] + $rlRowHalf + 14 - $rlListAreaX) * $rlU)
        [System.Windows.Controls.Canvas]::SetTop($r.Name, ($c[1] - $rlListAreaY) * $rlU - $r.Name.DesiredSize.Height / 2)
        # padlock at the row's right end: white + closed when locked
        $p = $rlPadlocks[$i]
        $p.Text = [string][char]$(if ($r.Last.Empty) { 0xE710 } elseif ($r.Locked) { 0xE72E } else { 0xE785 })   # + / closed / open padlock
        $grey = if ($r.Locked -or $r.Last.Empty) { 245 } else { 110 }   # bright = locked, or the "+" you can click
        $p.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb($grey, $grey, $grey))
        $p.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
        [System.Windows.Controls.Canvas]::SetLeft($p, ($rlListX + $rlListW - $rlListPad - $rlLockW - $rlListAreaX) * $rlU)
        [System.Windows.Controls.Canvas]::SetTop($p, ($c[1] - $rlListAreaY) * $rlU - $p.DesiredSize.Height / 2)
    }
    # header: < ROLL n/N >  (n = 1 for the newest)
    $n = @(Get-RouletteHistory).Count   # @(): one saved roll would otherwise come back as the roll itself
    $past = $script:rlHistIdx -gt 0
    $rlHistText.Text = if ($script:rlClearArmed -and $n) { 'CLEAR ALL? CLICK AGAIN' } elseif ($past) { 'PAST ROLL {0}/{1}' -f ($script:rlHistIdx + 1), $n } elseif ($n) { 'CURRENT ROLL' } else { '' }
    $rlHistPrev.Visibility = if ($past -and $script:rlHistIdx + 1 -lt $n) { 'Visible' } else { 'Hidden' }
    $rlHistNext.Visibility = if ($past -and $script:rlHistIdx -gt 1) { 'Visible' } else { 'Hidden' }
    $rlHistBtn.Visibility = if ($n -gt 1) { 'Visible' } else { 'Hidden' }
    $hb = if ($past) { 245 } else { 150 }
    $rlHistBtn.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb($hb, $hb, $hb))
    foreach ($p in $rlPadlocks) { $p.Visibility = if ($past) { 'Hidden' } else { 'Visible' } }   # nothing to lock or fill on a past roll
    $rlEquipNote.Text = if ($past) { 'PAST ROLL - VIEW ONLY' } else { 'REMEMBER TO EQUIP THESE PERKS' }
    $rlHistClear.Visibility = if ($n) { 'Visible' } else { 'Hidden' }
    $g = if ($script:rlClearArmed) { [System.Windows.Media.Color]::FromRgb(230, 70, 60) } else { [System.Windows.Media.Color]::FromRgb(150, 150, 150) }
    $rlHistClear.Foreground = New-Object System.Windows.Media.SolidColorBrush $g; $rlHistText.Foreground = New-Object System.Windows.Media.SolidColorBrush $(if ($script:rlClearArmed) { $g } else { [System.Windows.Media.Color]::FromRgb(170, 170, 170) })
    $hy = ($rlListY + $rlListPad + $rlHeadH / 2 - $rlListAreaY) * $rlU
    foreach ($t in $rlHistBtn, $rlHistPrev, $rlHistText, $rlHistNext, $rlHistClear) { $t.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity)) }
    # [clock] [<]   PAST ROLL 2/10   [>] [bin]
    [System.Windows.Controls.Canvas]::SetLeft($rlHistBtn, ($rlListX + $rlListPad + $rlRowInset - $rlListAreaX) * $rlU)
    [System.Windows.Controls.Canvas]::SetLeft($rlHistPrev, ($rlListX + $rlListPad + $rlRowInset + $rlLockW - $rlListAreaX) * $rlU)
    [System.Windows.Controls.Canvas]::SetLeft($rlHistText, ($rlListX + $rlListW / 2 - $rlListAreaX) * $rlU - $rlHistText.DesiredSize.Width / 2)
    [System.Windows.Controls.Canvas]::SetLeft($rlHistNext, ($rlListX + $rlListW - $rlListPad - $rlLockW - $rlListAreaX) * $rlU - $rlHistNext.DesiredSize.Width)
    [System.Windows.Controls.Canvas]::SetLeft($rlHistClear, ($rlListX + $rlListW - $rlListPad - $rlLockW - $rlListAreaX) * $rlU)   # over the padlock column
    foreach ($t in $rlHistBtn, $rlHistPrev, $rlHistText, $rlHistNext, $rlHistClear) { [System.Windows.Controls.Canvas]::SetTop($t, $hy - $t.DesiredSize.Height / 2) }
    $rlEquipNote.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
    [System.Windows.Controls.Canvas]::SetLeft($rlEquipNote, ($rlListX + $rlListW / 2 - $rlListAreaX) * $rlU - $rlEquipNote.DesiredSize.Width / 2)
    [System.Windows.Controls.Canvas]::SetTop($rlEquipNote, ($rlListY + $rlListH - $rlListPad - $rlFootH / 2 - $rlListAreaY) * $rlU - $rlEquipNote.DesiredSize.Height / 2)
}

# ---- Tooltip: hovering a result row shows that perk's description (just the
# description - user, 3 Nov), like the
# game's own tooltips (user, 3 Nov). Text: data\perk-text.json (DbD wiki,
# CC BY-SA). A click-through window LEFT of the results box. ----
$rlPerkText = $null
try { $rlPerkText = Get-Content (Join-Path $root 'data\perk-text.json') -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
$rlTipW = 380   # 1080p px
$rlTipWin = New-OverlayWindow 'DbD Clock Overlay roulette tooltip'
$rlTipBox = New-Object System.Windows.Controls.Border
$rlTipBox.Width = $rlTipW * $rlU
$rlTipBox.BorderBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(24, 24, 26)); $rlTipBox.BorderThickness = 1 * $rlU
Set-RouletteBoxLook $rlTipBox (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(245, 12, 12, 13)))
$rlTipGrid = New-Object System.Windows.Controls.Grid
[void]$rlTipGrid.Children.Add((New-RouletteFrame 4))
$rlTipStack = New-Object System.Windows.Controls.StackPanel
$rlTipStack.Margin = New-Object System.Windows.Thickness (16 * $rlU), (12 * $rlU), (16 * $rlU), (14 * $rlU)
function New-RouletteTipText([double]$size, [string]$weight, [byte]$grey, [double]$below) {
    $t = New-Object System.Windows.Controls.TextBlock
    $t.FontFamily = $rlFont; $t.FontSize = $size * $rlU; $t.FontWeight = $weight; $t.TextWrapping = 'Wrap'
    $t.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb($grey, $grey, $grey))
    $t.Margin = New-Object System.Windows.Thickness 0, 0, 0, ($below * $rlU)
    [void]$rlTipStack.Children.Add($t); $t
}
$rlTipDesc = New-RouletteTipText 13 'Normal' 215 0
$rlTipDesc.LineHeight = 18 * $rlU
# The description coloured the way DbD's own tooltips are (user, 3 Nov): tier
# values like 20/25/30 in the tier colours (green / blue / purple), other values
# with a unit in DbD's yellow, status effects (Elusive, Haste ...) bold.
$rlTipCol = @{
    T1 = [System.Windows.Media.Color]::FromRgb(25, 155, 30); T2 = [System.Windows.Media.Color]::FromRgb(47, 156, 214); T3 = [System.Windows.Media.Color]::FromRgb(172, 62, 227)
    Val = [System.Windows.Media.Color]::FromRgb(232, 194, 82); Sep = [System.Windows.Media.Color]::FromRgb(150, 150, 150)
}
$rlTipRx = New-Object System.Text.RegularExpressions.Regex ('(?<tier>[+-]?\d+(?:\.\d+)?/[+-]?\d+(?:\.\d+)?/[+-]?\d+(?:\.\d+)?)' +
    '|(?<val>[+-]?\d+(?:\.\d+)?\s?(?:%|seconds?|second\(s\)|metres?|meters?|Tokens?|Token\(s\)|Charges?)(?![\w/]))' +
    '|(?<se>\b(?:Haste|Hindered|Exhausted|Exposed|Elusive|Endurance|Undetectable|Oblivious|Blindness|Broken|Haemorrhage|Mangled|Deep Wound|Incapacitated|Cursed|Bloodlust)(?:\sStatus Effects?)?\b)')
function Set-RouletteTipText($tb, [string]$text) {
    $tb.Inlines.Clear()
    $add = { param($t, $col, $bold) $r = New-Object System.Windows.Documents.Run $t; if ($col) { $r.Foreground = New-Object System.Windows.Media.SolidColorBrush $col }; if ($bold) { $r.FontWeight = 'Bold' }; $tb.Inlines.Add($r) }
    $at = 0
    foreach ($m in $rlTipRx.Matches($text)) {
        if ($m.Index -gt $at) { & $add $text.Substring($at, $m.Index - $at) $null $false }
        if ($m.Groups['tier'].Success) {
            $p = $m.Value -split '/'
            & $add $p[0] $rlTipCol.T1 $true; & $add '/' $rlTipCol.Sep $false; & $add $p[1] $rlTipCol.T2 $true; & $add '/' $rlTipCol.Sep $false; & $add $p[2] $rlTipCol.T3 $true
        } elseif ($m.Groups['val'].Success) { & $add $m.Value $rlTipCol.Val $true }
        else { & $add $m.Value $rlTipCol.Val $true }   # status effect
        $at = $m.Index + $m.Length
    }
    if ($at -lt $text.Length) { & $add $text.Substring($at) $null $false }
}[void]$rlTipGrid.Children.Add($rlTipStack)
$rlTipBox.Child = $rlTipGrid
$rlTipWin.Content = $rlTipBox
$rlTipRow = -1
function Hide-RouletteTip { $script:rlTipRow = -1; if ($rlTipWin.IsVisible) { $rlTipWin.Hide() } }
function Show-RouletteTip([int]$i) {
    $perk = $rlReelsUi[$i].Last
    if ($i -eq $script:rlTipRow) { return }
    $side = if ($script:rlRole -eq 'killer') { 'killer' } else { 'survivor' }
    $desc = if ($rlPerkText) { [string]$rlPerkText.$side.($perk.name) } else { '' }
    if (-not $desc) { Hide-RouletteTip; return }
    $script:rlTipRow = $i
    Set-RouletteTipText $rlTipDesc $desc
    $rlTipBox.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
    $h = $rlTipBox.DesiredSize.Height / $rlU   # 1080p px
    # right edge 10 px left of the box; top level with the row, kept on screen
    $c = Get-RouletteRowCentre $i
    $top = [Math]::Max(10, [Math]::Min($c[1] - $rlRowH / 2, 1070 + $rlListDY - $h))
    $rlTipWin.Left = ($rlListX - 10 - $rlTipW) * $rlU + $rlX0 + $rlOff; $rlTipWin.Top = $top * $rlU + $rlY0
    if (-not $rlTipWin.IsVisible) { $rlTipWin.Show() }
}
# which row the mouse is over (the name / diamond part, not the padlock column)
$rlListCanvas.Add_MouseMove({
    param($s, $e)
    $p = $e.GetPosition($rlListCanvas)
    $x = $p.X / $rlU + $rlListAreaX; $y = $p.Y / $rlU + $rlListAreaY
    $row = -1
    if ($rlListPanel.Opacity -gt 0.5 -and -not $script:rlSpinning -and $x -ge $rlListX + $rlListPad -and $x -lt $rlListX + $rlListW - $rlListPad - $rlLockW) {
        for ($i = 0; $i -lt 4; $i++) {
            $c = Get-RouletteRowCentre $i
            if ([Math]::Abs($y - $c[1]) -le $rlRowH / 2) { $row = $i }
        }
    }
    if ($row -ge 0 -and $rlReelsUi[$row].Last -and -not $rlReelsUi[$row].Last.Empty -and -not $rlReelsUi[$row].Filling) { Show-RouletteTip $row } else { Hide-RouletteTip }
})
$rlListCanvas.Add_MouseLeave({ Hide-RouletteTip })

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
    if (-not $script:rlDebug) { [void][OverlayNative]::SetWindowDisplayAffinity($h, 0x11) }
})
$rlButton = New-Object System.Windows.Controls.Border
# SPIN + THEME sit top right, just under the Auric Cells / Iridescent Shards /
# Bloodpoints row, right edges lined up (user, 3 Nov: over the perk row they
# covered the add-on and offering tooltips). That corner is pinned to the
# screen's right, like the chat box: $rlListDX moves them with it.
# a scaled-down DbD SEARCH box (247 x 55 at 1080p, 24 px text): box, frame and text all at
# the same ratio (user, 3 Nov: "the ratio is off", then "really big" at full size)
$rlBtnH = 36; $rlBtnScale = $rlBtnH / 55
$rlBtnW = 92; $rlThemeW = 176; $rlThemeGap = 6; $rlBtnFont = 24 * $rlBtnScale
$rlBtnRight = 1695; $rlBtnTop = 118                    # under the currency row (its dark band ends at y 110 - a gap, user 3 Nov), clear of DbD's perk diamonds (x 1680+ from y 145)
$rlBtnCX = $rlBtnRight - $rlThemeW - $rlThemeGap - $rlBtnW / 2; $rlBtnCY = $rlBtnTop + $rlBtnH / 2
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

# a round-ish spot on a wide button: radius as a share of the button's width / height
Set-RouletteBoxLook $rlButton $rlBtnBrush
function Set-RouletteGlow($e, $el = $rlButton) {   # $el = the box under the mouse (SPIN or THEME)
    $p = $e.GetPosition($el)
    $w = [Math]::Max(1.0, $el.ActualWidth); $h = [Math]::Max(1.0, $el.ActualHeight)
    $c = New-Object System.Windows.Point ([Math]::Min(1.0, [Math]::Max(0.0, $p.X / $w))), ([Math]::Min(1.0, [Math]::Max(0.0, $p.Y / $h)))
    $rlBtnGlow.Center = $c; $rlBtnGlow.GradientOrigin = $c
}
$rlBtnGrid = New-Object System.Windows.Controls.Grid
$rlBtnFrame = New-RouletteFrame 3 $rlBtnScale; [void]$rlBtnGrid.Children.Add($rlBtnFrame)
$rlBtnText = New-Object System.Windows.Controls.TextBlock
$rlBtnText.Text = 'SPIN'
$rlBtnText.FontFamily = $rlFont; $rlBtnText.FontWeight = 'Bold'; $rlBtnText.FontSize = $rlBtnFont * $rlU
$rlBtnText.HorizontalAlignment = 'Center'; $rlBtnText.VerticalAlignment = 'Center'
$rlBtnText.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(226, 226, 226))
[void]$rlBtnGrid.Children.Add($rlBtnText)
$rlButton.Child = $rlBtnGrid
$rlButton.Add_MouseEnter({ param($s, $e) Set-RouletteGlow $e; $rlBtnFrame.Tag.Fill = $rlBtnGlow })
$rlButton.Add_MouseMove({ param($s, $e) Set-RouletteGlow $e })
$rlButton.Add_MouseLeave({ $rlBtnFrame.Tag.Fill = $null })
$rlButton.Add_MouseLeftButtonUp({ Start-PerkSpin })

function Get-RouletteRole { if ($sync.KillerLoadout -or $env:DBD_OVERLAY_SPIN -eq 'killer') { 'killer' } else { 'survivor' } }
# ---- THEME: a second box right of SPIN, same style. Click = a drop-down list
# of themes under it. Remembered per side (by name) in roulette-settings.json. ----
# named after the words players use for builds (user, 3 Nov: "look up the
# typical keywords the community uses")
$rlThemes = @{
    survivor = @(@{ K = 'any'; L = 'ANY' }, @{ K = 'exhaustion'; L = 'EXHAUSTION' }, @{ K = 'antitunnel'; L = 'ANTI-TUNNEL & CAMP' }, @{ K = 'antislug'; L = 'ANTI-SLUG' },
                 @{ K = 'info'; L = 'INFO' }, @{ K = 'genrush'; L = 'GEN RUSH' }, @{ K = 'chase'; L = 'CHASE' },
                 @{ K = 'altruism'; L = 'ALTRUISM' }, @{ K = 'stealth'; L = 'STEALTH' }, @{ K = 'endgame'; L = 'ENDGAME' }, @{ K = 'items'; L = 'ITEMS & GADGETS' },
                 @{ K = 'boon'; L = 'BOON & TOTEM' }, @{ K = 'char'; L = 'ADEPT' })
    killer   = @(@{ K = 'any'; L = 'ANY' }, @{ K = 'slowdown'; L = 'SLOWDOWN' }, @{ K = 'tracking'; L = 'TRACKING' }, @{ K = 'antiloop'; L = 'ANTI-LOOP' },
                 @{ K = 'snowball'; L = 'SNOWBALL' }, @{ K = 'antiheal'; L = 'ANTI-HEAL' }, @{ K = 'antiexhaustion'; L = 'ANTI-EXHAUSTION' },
                 @{ K = 'obsession'; L = 'OBSESSION' }, @{ K = 'hex'; L = 'HEX' }, @{ K = 'scourge'; L = 'SCOURGE HOOK' },
                 @{ K = 'endgame'; L = 'ENDGAME' }, @{ K = 'stealth'; L = 'STEALTH' }, @{ K = 'char'; L = 'ADEPT' })
}
$rlSettingsPath = Join-Path $root 'roulette-settings.json'
$rlTheme = @{ survivor = 0; killer = 0 }
try {
    if (Test-Path $rlSettingsPath) {
        $sv = Get-Content $rlSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($k in 'survivor', 'killer') {
            $key = switch ([string]$sv.$k) { 'anticamp' { 'antitunnel' } 'gadgets' { 'items' } default { $_ } }   # themes merged 3 Nov
            for ($i = 0; $i -lt $rlThemes[$k].Count; $i++) { if ($rlThemes[$k][$i].K -eq $key) { $rlTheme[$k] = $i } }
        }
    }
} catch {}
function Get-RouletteTheme { $side = Get-RouletteRole; $rlThemes[$side][$rlTheme[$side]] }
$rlThemeBtn = New-Object System.Windows.Controls.Border
$rlThemeBtn.Width = $rlThemeW * $rlU; $rlThemeBtn.Height = $rlBtnH * $rlU
$rlThemeBtn.Margin = New-Object System.Windows.Thickness ($rlThemeGap * $rlU), 0, 0, 0
$rlThemeBtn.Cursor = [System.Windows.Input.Cursors]::Hand
$rlThemeBtn.BorderBrush = $rlButton.BorderBrush; $rlThemeBtn.BorderThickness = $rlButton.BorderThickness
Set-RouletteBoxLook $rlThemeBtn $rlBtnBrush
$rlThemeGrid = New-Object System.Windows.Controls.Grid
$rlThemeFrame = New-RouletteFrame 3 $rlBtnScale; [void]$rlThemeGrid.Children.Add($rlThemeFrame)
$rlThemeText = New-Object System.Windows.Controls.TextBlock
$rlThemeText.FontFamily = $rlFont; $rlThemeText.FontWeight = 'Bold'; $rlThemeText.FontSize = $rlBtnFont * $rlU
$rlThemeText.HorizontalAlignment = 'Center'; $rlThemeText.VerticalAlignment = 'Center'
$rlThemeText.Foreground = $rlBtnText.Foreground
# long theme names shrink to fit (never grow)
$rlThemeFit = New-Object System.Windows.Controls.Viewbox
$rlThemeFit.StretchDirection = 'DownOnly'; $rlThemeFit.Child = $rlThemeText
$rlThemeFit.Margin = New-Object System.Windows.Thickness (12 * $rlU), 0, (12 * $rlU), 0
[void]$rlThemeGrid.Children.Add($rlThemeFit)
$rlThemeBtn.Child = $rlThemeGrid
function Update-RouletteThemeLabel { $t = 'THEME: ' + (Get-RouletteTheme).L + '  ' + [char]0x25BE; if ($rlThemeText.Text -ne $t) { $rlThemeText.Text = $t } }
function Set-RouletteTheme([int]$i) {
    $side = Get-RouletteRole
    $rlTheme[$side] = $i
    Update-RouletteThemeLabel; Close-RouletteThemeList
    $save = [pscustomobject]@{ survivor = $rlThemes.survivor[$rlTheme.survivor].K; killer = $rlThemes.killer[$rlTheme.killer].K }
    try { [IO.File]::WriteAllText($rlSettingsPath, (ConvertTo-Json $save), (New-Object Text.UTF8Encoding $false)) } catch {}
}
# the drop-down: one box per theme under THEME, the current one lit
$rlThemeList = New-Object System.Windows.Controls.StackPanel
$rlThemeList.Margin = New-Object System.Windows.Thickness (($rlBtnW + $rlThemeGap) * $rlU), (3 * $rlU), 0, 0
$rlThemeList.HorizontalAlignment = 'Left'; $rlThemeList.Visibility = 'Collapsed'
$rlItemBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(240, 12, 12, 13))
$rlItemLit   = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(245, 46, 46, 50))
$rlItemHover = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(245, 70, 70, 76))
function Open-RouletteThemeList {
    $rlThemeList.Children.Clear()
    $side = Get-RouletteRole
    for ($i = 0; $i -lt $rlThemes[$side].Count; $i++) {
        $b = New-Object System.Windows.Controls.Border
        $b.Width = $rlThemeW * $rlU; $b.Height = 27 * $rlU; $b.Cursor = [System.Windows.Input.Cursors]::Hand; $b.Tag = $i
        $b.BorderBrush = New-Object System.Windows.Media.SolidColorBrush $rlEdge; $b.BorderThickness = New-Object System.Windows.Thickness (1 * $rlU), 0, (1 * $rlU), (1 * $rlU)
        $lit = $i -eq $rlTheme[$side]
        $b.Background = if ($lit) { $rlItemLit } else { $rlItemBrush }
        $tx = New-Object System.Windows.Controls.TextBlock
        $tx.Text = $rlThemes[$side][$i].L; $tx.FontFamily = $rlFont; $tx.FontWeight = 'Bold'; $tx.FontSize = 14 * $rlU
        $tx.HorizontalAlignment = 'Center'; $tx.VerticalAlignment = 'Center'
        $tx.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb($(if ($lit) { 255 } else { 200 }), $(if ($lit) { 255 } else { 200 }), $(if ($lit) { 255 } else { 200 })))
        $b.Child = $tx
        $b.Add_MouseEnter({ param($s, $e) $s.Background = $rlItemHover })
        $b.Add_MouseLeave({ param($s, $e) $s.Background = if ([int]$s.Tag -eq $rlTheme[(Get-RouletteRole)]) { $rlItemLit } else { $rlItemBrush } })
        $b.Add_MouseLeftButtonUp({ param($s, $e) Set-RouletteTheme ([int]$s.Tag) })
        [void]$rlThemeList.Children.Add($b)
    }
    $rlThemeList.Visibility = 'Visible'
}
function Close-RouletteThemeList { $rlThemeList.Visibility = 'Collapsed' }
$rlThemeBtn.Add_MouseEnter({ param($s, $e) Set-RouletteGlow $e $rlThemeBtn; $rlThemeFrame.Tag.Fill = $rlBtnGlow })
$rlThemeBtn.Add_MouseMove({ param($s, $e) Set-RouletteGlow $e $rlThemeBtn })
$rlThemeBtn.Add_MouseLeave({ $rlThemeFrame.Tag.Fill = $null })
$rlThemeBtn.Add_MouseLeftButtonUp({ if ($script:rlSpinning) { return }; if ($rlThemeList.Visibility -eq 'Visible') { Close-RouletteThemeList } else { Open-RouletteThemeList } })
Update-RouletteThemeLabel

# The 4 picks for a spin, following the theme. $keep = perks locked in place.
#   tag themes: from perks with that tag (topped up at random if there aren't enough)
#   exhaustion: exactly ONE exhaustion perk in the build (only one works at a time)
#   char: one random character's own perks (each has 3) + random to fill
function Get-RoulettePicks($pool, $keep) {
    $theme = (Get-RouletteTheme).K
    $need = 4 - @($keep).Count
    $free = @($pool | Where-Object { $_.name -notin @($keep | ForEach-Object { $_.name }) })
    $take = { param($from, $n) if ($n -le 0 -or -not @($from).Count) { @() } else { @($from | Get-Random -Count ([Math]::Min($n, @($from).Count))) } }
    $picks = switch ($theme) {
        'exhaustion' {
            $hasOne = @($keep | Where-Object { $_.tags -contains 'exhaustion' }).Count -gt 0
            $one = @(if (-not $hasOne) { & $take @($free | Where-Object { $_.tags -contains 'exhaustion' }) 1 })   # @(): one pick must stay a list
            $one + @(& $take @($free | Where-Object { $_.tags -notcontains 'exhaustion' }) ($need - $one.Count))
        }
        'char' {
            # ADEPT: one character's own 3 perks, then the last slot EMPTY by default
            # (the achievement uses only those 3; "+" on that row fills it if you want)
            # a locked character's perk keeps that character. All 3 locked = nothing of
            # theirs left to roll, so the 4th gets a perk (user, 3 Nov: "it should land
            # on something") - empty is only for a spin that rolls the character's perks
            $lockedChar = @($keep | Where-Object { $_.character -and $_.character -ne 'All' } | ForEach-Object { $_.character }) | Select-Object -First 1
            $chars = if ($lockedChar) { @($free | Where-Object { $_.character -eq $lockedChar } | Group-Object character) }
                     else { @($free | Where-Object { $_.character -and $_.character -ne 'All' } | Group-Object character | Where-Object Count -ge 3) }
            $grp = if ($chars.Count) { $chars | Get-Random }
            $own = @(if ($grp) { & $take @($grp.Group) $need })
            $rest = $need - $own.Count
            $empty = @(if ($rest -gt 0 -and $own.Count) { New-RouletteEmpty $grp.Name })
            $noShuffle = $true   # the empty slot stays last
            $own + $empty + @(& $take @($free | Where-Object { $_.name -notin @($own | ForEach-Object { $_.name }) }) ($rest - $empty.Count))
        }
        'any' { & $take $free $need }
        default {
            # a small theme (under 12 perks) gives 2 of its perks and 2 from the whole pool,
            # so it doesn't come up as the same build every time (user, 3 Nov)
            $all = @($pool | Where-Object { $_.tags -contains $theme })
            $n = if ($all.Count -lt 12) { [Math]::Max(0, 2 - @($keep | Where-Object { $_.tags -contains $theme }).Count) } else { $need }
            $tagged = @(& $take @($free | Where-Object { $_.tags -contains $theme }) ([Math]::Min($n, $need)))
            $tagged + @(& $take @($free | Where-Object { $_.name -notin @($tagged | ForEach-Object { $_.name }) }) ($need - $tagged.Count))
        }
    }
    if ($noShuffle) { @($picks) } else { @($picks | Get-Random -Count @($picks).Count) }   # shuffle, so a themed perk isn't always on slot 1
}

# SPIN + THEME side by side in the button window
$rlBtnRow = New-Object System.Windows.Controls.StackPanel
$rlBtnRow.Orientation = 'Horizontal'; $rlBtnRow.HorizontalAlignment = 'Left'; $rlBtnRow.VerticalAlignment = 'Top'
[void]$rlBtnRow.Children.Add($rlButton); [void]$rlBtnRow.Children.Add($rlThemeBtn)
# the buttons, with the theme drop-down opening under THEME
$rlBtnStack = New-Object System.Windows.Controls.StackPanel
$rlBtnStack.HorizontalAlignment = 'Left'; $rlBtnStack.VerticalAlignment = 'Top'
[void]$rlBtnStack.Children.Add($rlBtnRow); [void]$rlBtnStack.Children.Add($rlThemeList)

$rlBtnWindow.Content = $rlBtnStack

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
# everything that fades in with the names: names, padlocks, history header
function Get-RouletteNames { @($rlReelsUi | ForEach-Object { $_.Name }) + @($rlPadlocks) + @($rlHistBtn, $rlHistPrev, $rlHistText, $rlHistNext, $rlHistClear, $rlEquipNote) }
function Hide-RouletteList {
    Hide-RouletteTip
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
    Write-RouletteLog ('result shown: ' + (($rlReelsUi | ForEach-Object { if ($_.Last.Empty) { '(empty)' } else { $_.Last.name } }) -join ', '))
    for ($i = 0; $i -lt 4; $i++) {
        $r = $rlReelsUi[$i]
        Reset-RouletteReelAnims $r
        $r.Strip.Children.Clear(); [void]$r.Strip.Children.Add((New-RouletteIcon $r.Last))
        $r.Move.Y = ($rlD - $rlPitch) / 2
        $c = Get-RouletteRowCentre $i
        Set-ReelAt $r $c[0] $c[1] $rlRowScale
        $r.Done = $true; $r.Cell.Visibility = 'Visible'; Set-ReelRolling $r $false
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
        foreach ($r in $rlReelsUi) { $r.Cell.CacheMode = $null }   # live again for re-rolls
        Write-RouletteLog ('slide done: ' + (($rlReelsUi | ForEach-Object { "$($_.Last.name) vis=$($_.Cell.Visibility) win=$($_.Win.IsVisible) kids=$($_.Strip.Children.Count)" }) -join ' | '))
        Add-RouletteHistory   # newest roll = ROLL 1/n
        Set-RouletteNames
        Show-RouletteFade (Get-RouletteNames) 0
        $script:rlSpinning = $false; $script:rlHasResult = $true
        $rlBtnRow.Opacity = 1
    }
}
function Stop-RouletteSlide {
    foreach ($r in $rlReelsUi) { $r.Cell.CacheMode = $null }
    if ($rlSlide.On) { [System.Windows.Media.CompositionTarget]::remove_Rendering($rlSlideTick); $rlSlide.On = $false }
}
# after the last reel locks: the panel fades in during a short pause, then each
# diamond slides into its row
$rlListTimer = New-Object System.Windows.Threading.DispatcherTimer
$rlListTimer.Interval = [TimeSpan]::FromMilliseconds(650)
$rlListTimer.Add_Tick({
    $this.Stop()
    if (-not $script:rlSpinning) { return }
    foreach ($r in $rlReelsUi) {
        Reset-RouletteReelAnims $r   # the pop / rim flash are over by now
        # just the landed icon (the spin's long strip looks the same from here) ...
        $r.Strip.Children.Clear(); [void]$r.Strip.Children.Add((New-RouletteIcon $r.Last)); $r.Move.Y = ($rlD - $rlPitch) / 2
        # ... so the reel can be kept as one small picture for the slide, which then
        # only resizes it (icons blinked out mid-slide, 3 Nov). Only for the slide: a
        # spin's tall strip is too big to cache and drew nothing (re-rolls, 3 Nov).
        $r.Cell.CacheMode = New-Object System.Windows.Media.BitmapCache
    }
    $rlSlide.From = @(0..3 | ForEach-Object { ,(Get-RouletteSlotCentre $_) })
    $rlSlide.To = @(0..3 | ForEach-Object { ,(Get-RouletteRowCentre $_) })
    $rlSlide.Last = $null; $rlSlide.El = 0.0; $rlSlide.Hold = 0; $rlSlide.On = $true
    [System.Windows.Media.CompositionTarget]::add_Rendering($rlSlideTick)
})

# rolling: the strip is cut at the slot's outer edge (icons pass over the rim);
# landed: just the winner, unclipped, on top of the rim like an equipped perk (user, 3 Nov)
function Set-ReelRolling($r, [bool]$on) {
    if ($on) { $r.Clipper.Clip = $r.ClipGeo; if ($r.Ring) { $r.Ring.Visibility = 'Visible' }; return }
    $r.Move.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $null)
    $r.Strip.Children.Clear(); [void]$r.Strip.Children.Add((New-RouletteIcon $r.Last)); $r.Move.Y = ($rlD - $rlPitch) / 2
    $r.Clipper.Clip = $null; if ($r.Ring) { $r.Ring.Visibility = 'Collapsed' }
}
function New-RouletteIcon($perk) {
    $g = New-Object System.Windows.Controls.Grid
    $g.Width = $rlD; $g.Height = $rlPitch
    if (-not $perk -or $perk.Empty) { return $g }   # an empty Adept slot: just the bare diamond
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
    # a spin called off (loadout left) still finishes its animations: ignore them,
    # or they'd slide an empty result into the list and history
    if (-not $script:rlSpinning) { return }
    foreach ($r in $rlReelsUi) {
        if ($r.Done -or $r.Move.Y -gt $r.Target + 0.5) { continue }
        $r.Done = $true; Set-ReelRolling $r $false   # landed: icon on top of the rim
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
    Write-RouletteLog 'SPIN clicked'
    if ($script:rlSpinning -or (Test-RouletteFilling)) { return }
    # killer loadout = killer perks (user, 3 Nov: "it's doing surv perks");
    # DBD_OVERLAY_SPIN=killer tests that pool
    $script:rlRole = Get-RouletteRole
    $pool = if ($script:rlRole -eq 'killer') { @($perkDb.killerPerks) } else { @($perkDb.perks) }
    if ($pool.Count -lt 4) { return }
    $script:rlSpinning = $true; $script:rlHasResult = $false; Close-RouletteThemeList
    Stop-RouletteSlide
    $rlBtnRow.Opacity = 0.55   # dimmed while spinning
    $rlListTimer.Stop()
    Hide-RouletteList
    # locked rows keep their perk; the others get different perks, never one that's locked
    $keep = @($rlReelsUi | Where-Object { $_.Locked -and $_.Last } | ForEach-Object { $_.Last })
    $fresh = @(Get-RoulettePicks $pool $keep); $f = 0   # follows the THEME button
    if ($fresh.Count -lt 4 - $keep.Count) { $script:rlSpinning = $false; $rlBtnRow.Opacity = 1; return }
    $picks = @(0..3 | ForEach-Object { if ($rlReelsUi[$_].Locked -and $rlReelsUi[$_].Last) { $rlReelsUi[$_].Last } else { $fresh[$f]; $f++ } })
    $start = ($rlD - $rlPitch) / 2           # icons centred in the reel
    for ($i = 0; $i -lt 4; $i++) {
        $r = $rlReelsUi[$i]
        # back onto its slot, full size
        Reset-RouletteReelAnims $r
        $c = Get-RouletteSlotCentre $i
        Set-ReelAt $r $c[0] $c[1] 1.0
        $r.Cell.Visibility = 'Visible'; Set-ReelRolling $r $true
        $r.Done = $false; $r.Index = 0; $r.Start = $start
        $r.Strip.Children.Clear()
        if ($r.Locked -and $r.Last) {
            # locked: shows its perk and settles straight away (clunk, white flash)
            [void]$r.Strip.Children.Add((New-RouletteIcon $r.Last))
            $r.Target = $start
            $anim = New-Object System.Windows.Media.Animation.DoubleAnimation $start, $start, ([System.Windows.Duration][TimeSpan]::FromSeconds(0.25))
            $anim.Add_Completed($rlOnReelDone)
            $r.Move.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $anim)
            continue
        }
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
    @{ BtnLeft = ($rlBtnCX - $rlBtnW / 2 + $rlListDX) * $rlU; BtnTop = ($rlBtnCY - $rlBtnH / 2) * $rlU }   # pinned right (top stays top)
}
function Set-RoulettePosition {
    $l = Get-RouletteLayout
    $rlBtnWindow.Left = $l.BtnLeft + $rlX0 + $rlOff; $rlBtnWindow.Top = $l.BtnTop + $rlY0
    $rlListWin.Left = $rlListAreaX * $rlU + $rlX0 + $rlOff; $rlListWin.Top = $rlListAreaY * $rlU + $rlY0
    foreach ($r in $rlReelsUi) { Set-ReelAt $r $r.CX $r.CY $r.S }
}

# Tests: everything the roulette shows, drawn into one picture of the 1080p
# area (290,200)-(1920,880), for pasting onto a loadout screenshot
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
    $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap ([int](1630 * $rlU)), ([int](680 * $rlU)), 96, 96, ([System.Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($dv)
    $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [IO.File]::Create($path); $enc.Save($fs); $fs.Close()
}

# Called by the overlay's 0.5 s timer: shows only while the loadout panel is on
# screen (and the game is in front); hidden elsewhere. The result is kept for
# the lobby and cleared once a match starts (map detected or match HUD seen).
$rlRole = 'survivor'
function Update-Roulette {
    Update-RouletteThemeLabel   # killer and survivor have their own theme
    $inMatch =$sync.HaveMap -or ($sync.LastHud -and ((Get-Date) - $sync.LastHud).TotalSeconds -lt 10)
    # switched between killer and survivor: the last result was for the other side
    if (-not $script:rlSpinning -and (Get-RouletteRole) -ne $script:rlRole -and ($script:rlHasResult -or $rlReelsUi[0].Last)) {
        Write-RouletteLog "side switched to $(Get-RouletteRole): result cleared"
        $script:rlHasResult = $false
        foreach ($r in $rlReelsUi) { $r.Last = $null; $r.Locked = $false }
        if ($script:rlShown) { Hide-RouletteList; foreach ($r in $rlReelsUi) { $r.Cell.Visibility = 'Hidden' } }
        $script:rlRole = Get-RouletteRole; $script:rlHistIdx = 0
    }
    if ($inMatch -and ($script:rlHasResult -or $rlReelsUi[0].Last)) {
        Write-RouletteLog 'match started: result cleared'
        $script:rlHasResult = $false
        foreach ($r in $rlReelsUi) { $r.Last = $null; $r.Locked = $false }
    }
    # the latest screen read must show the loadout panel (reads come every ~2 s;
    # a stale "yes" from a stopped scanner doesn't count)
    $fresh = $sync.LastScan -and ((Get-Date) - $sync.LastScan).TotalSeconds -lt 4
    $show = $env:DBD_OVERLAY_SPIN -or ($sync.LoadoutNow -and $fresh -and $sync.DbdInFront)
    if ($show -ne $script:rlShown) { Write-RouletteLog ($(if ($show) { 'SHOW' } else { 'HIDE' }) + " (loadout $([bool]$sync.LoadoutNow), read $([bool]$fresh), DbD in front $([bool]$sync.DbdInFront), spinning $script:rlSpinning, result $script:rlHasResult)") }
    if ($show -and -not $script:rlShown) {
        $script:rlShown = $true
        # list first, so the reel windows stack above it
        $rlListWin.Show()
        # the reels and the tooltip belong to the list window, so Windows keeps them
        # ABOVE it: clicking a name / padlock raised the list's (solid) box over the
        # reels and hid their icons and pips (user, 3 Nov). Only possible once the list
        # window has been shown.
        if (-not $script:rlOwned) {
            foreach ($r in $rlReelsUi) { $r.Win.Owner = $rlListWin }
            $rlTipWin.Owner = $rlListWin
            $rlBtnWindow.Owner = $rlListWin   # SPIN / THEME too: the theme drop-down opens over the results box (user, 3 Nov)
            $script:rlOwned = $true
        }
        foreach ($r in $rlReelsUi) { $r.Win.Show() }; $rlBtnWindow.Show()
        Set-RoulettePosition
        if ($script:rlHasResult) { Show-RouletteResult }
    } elseif (-not $show -and $script:rlShown) {
        # left the loadout (even mid-spin): stop and put it away; a finished
        # result is kept for when the loadout opens again
        if ($script:rlSpinning) {
            $script:rlSpinning = $false
            $rlTickTimer.Stop(); $rlListTimer.Stop(); Stop-RouletteSlide
            foreach ($r in $rlReelsUi) { $r.Last = $null; $r.Locked = $false }   # an unfinished spin doesn't count
        }
        foreach ($r in $rlReelsUi) { $r.Filling = $false }; $rlTickTimer.Stop(); Hide-RouletteTip   # a re-roll's spin: its perk is already picked
        $script:rlShown = $false
        foreach ($r in $rlReelsUi) {
            $r.Move.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $null)
            $r.Done = $true; $r.Cell.Visibility = 'Hidden'
        }
        Hide-RouletteList
        Close-RouletteThemeList
        $rlListWin.Hide(); foreach ($r in $rlReelsUi) { $r.Win.Hide() }; $rlBtnWindow.Hide()
        $rlBtnRow.Opacity = 1
    }
}
