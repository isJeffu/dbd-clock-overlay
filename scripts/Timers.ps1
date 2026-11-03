# Perk timers (bottom middle of the screen) and the chase timer.
# Dot-sourced by ClockOverlay.ps1 after New-OverlayWindow exists.
#
# Which perks get a timer, and for how long, comes from perks.json ("timers",
# tier III seconds). What shows depends on the build you picked (PageUp):
#   unhook_you  you unhooked someone  - auto ("HOOK RESCUE" pop-up) or F4
#   unhooked    you were unhooked     - Insert
#   exhausted   you used your exhaustion perk - F3
#   match_start killer perks you chose to assume (Lethal Pursuer) - automatic
# With no build picked, a generic set is used (perks.json "generic").
# Icons come from the DbD wiki (Setup.ps1 downloads them into "icons").

$perkDb = Get-Content (Join-Path $root 'data\perks.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$timerGaps   = @(40, 190, 330)    # distance from the bottom of the screen: low, middle, high (Home cycles)
$timerScales = @(1.0, 1.4, 1.8)   # timer size: normal, bigger, biggest (End cycles)

$timerWindow = New-OverlayWindow 'DbD Clock Overlay timers'
$timerPanel = New-Object System.Windows.Controls.StackPanel
$timerPanel.Orientation = 'Horizontal'
$timerWindow.Content = $timerPanel
$timerScaleTransform = New-Object System.Windows.Media.ScaleTransform 1, 1
$timerPanel.LayoutTransform = $timerScaleTransform

$activeTimers = New-Object System.Collections.ArrayList   # @{ Label; Color; Icon; Total; Ends }
$chase = @{ Start = $null; Result = $null; ShowUntil = $null }

function New-TimerBrush([string]$hex) {
    [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString($hex))
}
$timerBack = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(190, 20, 20, 30))
$iconCache = @{}

function Get-PerkIconFile([string]$perkName) {
    $p = $perkDb.perks | Where-Object { $_.name -eq $perkName } | Select-Object -First 1
    if ($p) { $p.file } else { $null }
}

function Get-TimerIcon([string]$file) {
    if (-not $file) { return $null }
    if (-not $iconCache.ContainsKey($file)) {
        $path = Join-Path $root "icons\$file"
        $iconCache[$file] = if (Test-Path $path) {
            $bi = New-Object System.Windows.Media.Imaging.BitmapImage
            $bi.BeginInit(); $bi.UriSource = New-Object System.Uri $path; $bi.CacheOption = 'OnLoad'; $bi.DecodePixelWidth = 128; $bi.EndInit()
            $bi
        } else { $null }
    }
    $iconCache[$file]
}

function Format-Seconds([double]$s) {
    $s = [Math]::Max(0, [Math]::Floor($s))
    if ($s -ge 60) { '{0}:{1:00}' -f [int][Math]::Floor($s / 60), [int]($s % 60) } else { "$([int]$s)s" }
}

# One perk tile: icon on a coloured diamond (like the HUD), seconds left, and a bar
function New-PerkTile($t, [double]$left) {
    $tile = New-Object System.Windows.Controls.StackPanel
    $tile.Margin = '8,0,8,0'
    $grid = New-Object System.Windows.Controls.Grid
    $grid.Width = 64; $grid.Height = 64
    $diamond = New-Object System.Windows.Shapes.Rectangle
    $diamond.Width = 44; $diamond.Height = 44
    $diamond.Fill = $timerBack
    $diamond.Stroke = New-TimerBrush $t.Color; $diamond.StrokeThickness = 2.5
    $diamond.RenderTransformOrigin = '0.5,0.5'
    $diamond.RenderTransform = New-Object System.Windows.Media.RotateTransform 45
    [void]$grid.Children.Add($diamond)
    $icon = Get-TimerIcon $t.Icon
    if ($icon) {
        $img = New-Object System.Windows.Controls.Image
        $img.Source = $icon; $img.Width = 46; $img.Height = 46
        [void]$grid.Children.Add($img)
    } else {
        $lbl = New-Object System.Windows.Controls.TextBlock
        $lbl.Text = $t.Label; $lbl.FontFamily = 'Segoe UI'; $lbl.FontWeight = 'Bold'; $lbl.FontSize = 11
        $lbl.TextWrapping = 'Wrap'; $lbl.TextAlignment = 'Center'; $lbl.MaxWidth = 44
        $lbl.Foreground = New-TimerBrush $t.Color; $lbl.HorizontalAlignment = 'Center'; $lbl.VerticalAlignment = 'Center'
        [void]$grid.Children.Add($lbl)
    }
    [void]$tile.Children.Add($grid)
    $secs = New-Object System.Windows.Controls.TextBlock
    $secs.Text = [string][int][Math]::Ceiling($left)
    $secs.FontFamily = 'Segoe UI'; $secs.FontWeight = 'Bold'; $secs.FontSize = 16
    $secs.Foreground = [System.Windows.Media.Brushes]::White; $secs.HorizontalAlignment = 'Center'
    $secs.Effect = New-Object System.Windows.Media.Effects.DropShadowEffect -Property @{ ShadowDepth = 0; BlurRadius = 4; Color = [System.Windows.Media.Colors]::Black }
    [void]$tile.Children.Add($secs)
    $track = New-Object System.Windows.Controls.Grid
    $track.Width = 52; $track.Height = 5; $track.Margin = '0,2,0,0'
    $bg = New-Object System.Windows.Shapes.Rectangle
    $bg.Fill = New-TimerBrush '#50000000'; $bg.RadiusX = 2; $bg.RadiusY = 2
    $fg = New-Object System.Windows.Shapes.Rectangle
    $fg.Fill = New-TimerBrush $t.Color; $fg.RadiusX = 2; $fg.RadiusY = 2
    $fg.HorizontalAlignment = 'Left'; $fg.Width = [Math]::Max(0, 52 * $left / $t.Total)
    [void]$track.Children.Add($bg); [void]$track.Children.Add($fg)
    [void]$tile.Children.Add($track)
    $tile
}

# The chase timer has no perk, so it's a small pill
function New-ChaseTile([string]$text) {
    $b = New-Object System.Windows.Controls.Border
    $b.Background = $timerBack
    $b.CornerRadius = 8
    $b.Padding = '10,4,10,4'
    $b.Margin = '8,0,8,0'
    $b.VerticalAlignment = 'Center'
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $text; $tb.FontFamily = 'Segoe UI'; $tb.FontWeight = 'SemiBold'; $tb.FontSize = 15
    $tb.Foreground = New-TimerBrush '#C9A8FF'
    $b.Child = $tb
    $b
}

# perks.json stores seconds as [tier I, tier II, tier III]; the picker saves
# which tier you have (default III)
function Get-Tier([string]$perkName) {
    $t = $state.PerkTiers.$perkName
    if ($t -ge 1 -and $t -le 3) { [int]$t } else { 3 }
}
function Get-TierSeconds([string]$perkName, $seconds) {
    $s = @($seconds)
    if ($s.Count -ge 3) { [int]$s[(Get-Tier $perkName) - 1] } else { [int]$s[0] }
}

# Adds (or restarts) one countdown. Same label twice = restart it.
function Add-Timer([string]$label, [string]$icon, [string]$color, [int]$seconds) {
    foreach ($t in @($activeTimers)) { if ($t.Label -eq $label) { $activeTimers.Remove($t) } }
    [void]$activeTimers.Add(@{ Label = $label; Color = $color; Icon = $icon; Total = $seconds; Ends = (Get-Date).AddSeconds($seconds) })
}

# Starts every timer in your build for this trigger; with no build, the generic set.
# Returns how many it started.
function Start-EventTimers([string]$trigger, [string[]]$extraPerks = @()) {
    if (-not $state.TimersOn) { return 0 }   # timers switched off in settings.json
    $build = @($state.Perks)
    $wanted = if ($build.Count) { $build } else { @($perkDb.generic.$trigger) }
    $started = 0; $startedPerks = @()
    foreach ($t in $perkDb.timers) {
        if ($t.trigger -ne $trigger -or $wanted -notcontains $t.perk) { continue }
        Add-Timer $t.perk (Get-PerkIconFile $t.perk) $t.color (Get-TierSeconds $t.perk $t.seconds)
        $started++; $startedPerks += $t.perk
    }
    # Perks named on screen when you were unhooked (the rescuer's Borrowed Time,
    # Babysitter...): their effect is on you, so run their timer too
    if ($trigger -eq 'unhooked') {
        foreach ($t in $perkDb.timers) {
            if ($t.trigger -ne 'unhook_you' -or $extraPerks -notcontains $t.perk -or $startedPerks -contains $t.perk) { continue }
            Add-Timer $t.perk (Get-PerkIconFile $t.perk) $t.color (Get-TierSeconds $t.perk $t.seconds)
            $started++; $startedPerks += $t.perk
        }
    }
    # Things every Survivor gets without a perk (basekit Endurance after an
    # unhook). Borrowed Time's own timer already covers that, so skip it then.
    foreach ($b in @($perkDb.basekit)) {
        if (-not $b -or @($b.triggers) -notcontains $trigger) { continue }
        if ($startedPerks -contains 'Borrowed Time' -and -not $b.keepWithBT) { continue }
        if ($b.untilGates -and $sync.GatesPowered) { continue }   # e.g. unhook Elusive stops once all gens are done
        Add-Timer $b.name $b.file $b.color ([int]$b.seconds)
        $started++
    }
    if ($trigger -eq 'match_start' -and $state.AssumeLethal) {
        foreach ($k in $perkDb.killer) { if ($k.trigger -eq 'match_start') { Add-Timer $k.name $k.file $k.color (Get-TierSeconds $k.name $k.seconds); $started++ } }
    }
    Update-Timers
    $started
}

# Kept for older calls: "you unhooked someone"
function Start-UnhookTimers { [void](Start-EventTimers 'unhook_you') }

function Switch-Chase {
    if (-not $state.TimersOn -and -not $chase.Start) { return }
    if ($chase.Start) {
        $chase.Result = ((Get-Date) - $chase.Start).TotalSeconds
        $chase.Start = $null
        $chase.ShowUntil = (Get-Date).AddSeconds(15)
    } else {
        $chase.Start = Get-Date
        $chase.Result = $null
    }
    Update-Timers
}

function Reset-Timers {
    $activeTimers.Clear()
    $chase.Start = $null; $chase.Result = $null; $chase.ShowUntil = $null
    Update-Timers
}

function Update-Timers {
    $now = Get-Date
    if ($chase.ShowUntil -and $now -ge $chase.ShowUntil) { $chase.ShowUntil = $null; $chase.Result = $null }
    $timerScaleTransform.ScaleX = $timerScaleTransform.ScaleY = $timerScales[$state.TimerSize]
    $timerPanel.Children.Clear()
    foreach ($t in @($activeTimers)) {
        $left = ($t.Ends - $now).TotalSeconds
        if ($left -le 0) { $activeTimers.Remove($t); continue }
        [void]$timerPanel.Children.Add((New-PerkTile $t $left))
    }
    if ($chase.Start) {
        [void]$timerPanel.Children.Add((New-ChaseTile ('Chase ' + (Format-Seconds ($now - $chase.Start).TotalSeconds))))
    } elseif ($chase.Result -ne $null) {
        [void]$timerPanel.Children.Add((New-ChaseTile ('Chase lasted ' + (Format-Seconds $chase.Result))))
    }
    $timerWindow.Visibility = if ($timerPanel.Children.Count) { 'Visible' } else { 'Hidden' }
    # Bottom middle, above DbD's own prompts
    $timerWindow.UpdateLayout()
    $sw = [System.Windows.SystemParameters]::PrimaryScreenWidth
    $sh = [System.Windows.SystemParameters]::PrimaryScreenHeight
    $timerWindow.Left = ($sw - $timerWindow.ActualWidth) / 2
    $timerWindow.Top = $sh - $timerWindow.ActualHeight - $timerGaps[$state.TimerPos]
}

$timerTick = New-Object System.Windows.Threading.DispatcherTimer
$timerTick.Interval = [TimeSpan]::FromMilliseconds(250)
$timerTick.Add_Tick({ if ($activeTimers.Count -or $chase.Start -or $chase.ShowUntil) { Update-Timers } })

# ---------- Perk picker (PageUp): tick the perks you run ----------
function Show-PerkPicker {
    if ($script:perkPicker) { $script:perkPicker.Activate(); return }
    $sync.Paused = $true
    $p = New-Object System.Windows.Window
    $p.Title = 'Your perks - tick the ones you run (Esc to close)'
    $p.Width = 480; $p.Height = 640
    $p.WindowStartupLocation = 'CenterScreen'
    $p.Topmost = $true
    $p.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(30, 30, 40))
    $dock = New-Object System.Windows.Controls.DockPanel
    $dock.Margin = 10
    $box = New-Object System.Windows.Controls.TextBox
    $box.FontSize = 15; $box.Margin = '0,0,0,6'; $box.Padding = 4
    [System.Windows.Controls.DockPanel]::SetDock($box, 'Top')
    $top = New-Object System.Windows.Controls.DockPanel
    $top.Margin = '0,0,0,6'
    [System.Windows.Controls.DockPanel]::SetDock($top, 'Top')
    $clear = New-Object System.Windows.Controls.Button
    $clear.Content = 'Clear'; $clear.Margin = '10,0,0,0'; $clear.Padding = '8,2,8,2'
    [System.Windows.Controls.DockPanel]::SetDock($clear, 'Right')
    $chosen = New-Object System.Windows.Controls.TextBlock
    $chosen.Foreground = [System.Windows.Media.Brushes]::White; $chosen.FontSize = 13; $chosen.TextWrapping = 'Wrap'; $chosen.VerticalAlignment = 'Center'
    [void]$top.Children.Add($clear); [void]$top.Children.Add($chosen)
    $lethal = New-Object System.Windows.Controls.CheckBox
    $lethal.Content = 'Assume the killer has Lethal Pursuer (9 s aura read at the start)'
    $lethal.Foreground = [System.Windows.Media.Brushes]::White; $lethal.Margin = '0,0,0,8'
    $lethal.IsChecked = [bool]$state.AssumeLethal
    [System.Windows.Controls.DockPanel]::SetDock($lethal, 'Top')
    $auto = New-Object System.Windows.Controls.CheckBox
    $auto.Content = 'Read my perks from the lobby automatically (replaces the ticks below each lobby)'
    $auto.Foreground = [System.Windows.Media.Brushes]::White; $auto.Margin = '0,0,0,8'
    $auto.IsChecked = [bool]$state.AutoPerks
    [System.Windows.Controls.DockPanel]::SetDock($auto, 'Top')
    [void]$dock.Children.Add($auto)
    $list = New-Object System.Windows.Controls.ListBox
    $list.Background = $p.Background
    $list.Foreground = [System.Windows.Media.Brushes]::White
    $list.BorderThickness = 0
    [void]$dock.Children.Add($box); [void]$dock.Children.Add($top); [void]$dock.Children.Add($lethal); [void]$dock.Children.Add($list)
    $p.Content = $dock

    $picked = New-Object System.Collections.ArrayList
    foreach ($n in @($state.Perks)) { [void]$picked.Add($n) }
    $tiers = @{}
    foreach ($prop in @($state.PerkTiers.PSObject.Properties)) { $tiers[$prop.Name] = [int]$prop.Value }
    $refreshChosen = {
        $chosen.Text = if ($picked.Count) { "Picked ($($picked.Count)): " + (($picked | Sort-Object) -join ', ') } else { 'Nothing picked - generic timers will be used' }
    }
    $fill = {
        $q = $box.Text.Trim()
        $list.Items.Clear()
        foreach ($perk in $perkDb.perks) {
            if ($q -and $perk.name -notlike "*$q*") { continue }
            $row = New-Object System.Windows.Controls.DockPanel
            $row.LastChildFill = $true
            $cb = New-Object System.Windows.Controls.CheckBox
            $t = $perkDb.timers | Where-Object { $_.perk -eq $perk.name } | Select-Object -First 1
            $cb.Foreground = if ($t) { [System.Windows.Media.Brushes]::White } else { New-TimerBrush '#AAAAAA' }
            $cb.FontSize = 14; $cb.Margin = '0,2,0,2'; $cb.VerticalAlignment = 'Center'
            $cb.IsChecked = $picked.Contains($perk.name)
            $cb.Tag = $perk.name
            $cb.Add_Checked({ param($s, $e) if (-not $picked.Contains($s.Tag)) { [void]$picked.Add($s.Tag) }; & $refreshChosen })
            $cb.Add_Unchecked({ param($s, $e) $picked.Remove($s.Tag); & $refreshChosen })
            if ($t) {
                # Tier dropdown: I / II / III, showing that tier's seconds
                $combo = New-Object System.Windows.Controls.ComboBox
                $combo.Width = 92; $combo.Margin = '8,0,0,0'; $combo.FontSize = 12; $combo.VerticalAlignment = 'Center'
                $secs = @($t.seconds)
                foreach ($i in 0..2) { [void]$combo.Items.Add(('I', 'II', 'III')[$i] + "  $($secs[$i])s") }
                $combo.SelectedIndex = (Get-Tier $perk.name) - 1
                $combo.Tag = $perk.name
                $combo.Add_SelectionChanged({ param($s, $e) $tiers[$s.Tag] = $s.SelectedIndex + 1 })
                [System.Windows.Controls.DockPanel]::SetDock($combo, 'Right')
                [void]$row.Children.Add($combo)
                $cb.Content = "$($perk.name)   ($($t.note))"
            } else {
                $cb.Content = $perk.name
            }
            [void]$row.Children.Add($cb)
            [void]$list.Items.Add($row)
        }
    }
    & $fill; & $refreshChosen
    $box.Add_TextChanged($fill)
    $clear.Add_Click({ $picked.Clear(); & $fill; & $refreshChosen })
    $p.Add_PreviewKeyDown({ param($s, $e) if ($e.Key -eq 'Escape') { $p.Close(); $e.Handled = $true } })
    $p.Add_Closed({
        $state.Perks = @($picked)
        $state.PerkTiers = [pscustomobject]$tiers
        $state.AssumeLethal = [bool]$lethal.IsChecked
        $state.AutoPerks = [bool]$auto.IsChecked; $sync.AutoPerks = $state.AutoPerks
        Save-Settings
        $script:perkPicker = $null; $sync.Paused = $false
        Show-Hint ("Perks saved: " + $(if ($picked.Count) { $picked.Count } else { 'none (generic timers)' })) 4
    })
    $script:perkPicker = $p
    $p.Show(); $p.Activate(); [void]$box.Focus()
}
