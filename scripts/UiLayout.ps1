# Where DbD's own menus and HUD sit on this screen, so the overlay can find the
# loadout panel, the lobby perks and the collapse bar on any aspect ratio.
# DbD lays its UI out for 1920x1080 and scales it to fit (by height on wide
# screens, by width on tall ones); each panel is pinned to the left edge, the
# right edge or the middle. Positions here are 1080p "design pixels" + which
# side they're pinned to. On 16:9 every mode gives exactly the old numbers.
# "UiLayout" in settings.json:
#   "auto" (default) - panels pinned to the screen edges (DbD's behaviour on
#                      ultrawide as far as we know - its own "16:9 aspect
#                      ratio" option doesn't keep the menus inside, per a 2025
#                      BHVR bug report)
#   "16:9"           - everything inside a centred 16:9 area: try this if the
#                      SPIN button / perk reading / collapse countdown are off
#                      on an ultrawide screen
# Dot-sourced by ClockOverlay.ps1 (UI + detector) and Roulette.ps1's tests.

# $scale = DbD's own Menu / HUD scale setting (Get-DbdScales): DbD shrinks each
# panel towards the edge it's pinned to, so it simply multiplies every distance
# from the pin (Consy plays at 85% - the SPIN button sat 18% too far out, 2 Nov)
function Get-DbdUi([double]$w, [double]$h, [string]$mode = 'auto', [double]$scale = 1.0) {
    $u0 = [Math]::Min($w / 1920.0, $h / 1080.0)   # design px -> screen px at 100%
    $bw = 1920 * $u0; $bh = 1080 * $u0             # the 16:9 design area
    if ($mode -eq '16:9') { $left = ($w - $bw) / 2; $top = ($h - $bh) / 2 } else { $left = 0.0; $top = 0.0 }
    $right = if ($mode -eq '16:9') { $left + $bw } else { $w }
    @{ U = $u0 * $scale; Left = $left; Right = $right; Top = $top; CX = $w / 2 }
}

# DbD's "Menu scale" and "HUD scale" (Settings > Graphics), as fractions, from
# its own settings file (MenuScaleFactor / HudScaleFactor = 70..100). Read again
# at most every 10 s, so a change in game is picked up; 1.0 when not found.
$script:DbdScales = @{ Menu = 1.0; Hud = 1.0; At = [datetime]::MinValue }
function Get-DbdScales {
    if (((Get-Date) - $script:DbdScales.At).TotalSeconds -lt 10) { return $script:DbdScales }
    $menu = 1.0; $hud = 1.0
    try {
        # Steam: WindowsClient; other stores use their own folder - take the newest
        $ini = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'DeadByDaylight\Saved\Config\*\GameUserSettings.ini') -ErrorAction Stop |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($ini) {
            foreach ($l in [IO.File]::ReadAllLines($ini.FullName)) {
                if ($l -match '^\s*MenuScaleFactor\s*=\s*(\d+(\.\d+)?)') { $menu = [double]$Matches[1] / 100 }
                elseif ($l -match '^\s*HudScaleFactor\s*=\s*(\d+(\.\d+)?)') { $hud = [double]$Matches[1] / 100 }
            }
        }
    } catch {}
    $clamp = { param($v) if ($v -lt 0.5 -or $v -gt 1.5) { 1.0 } else { $v } }
    $script:DbdScales = @{ Menu = (& $clamp $menu); Hud = (& $clamp $hud); At = Get-Date }
    $script:DbdScales
}
# x of a design-pixel position pinned 'left', 'right' or 'center'; y from the top
function Get-DbdX($ui, [double]$px, [string]$pin) {
    switch ($pin) {
        'left'  { $ui.Left + $px * $ui.U }
        'right' { $ui.Right - (1920 - $px) * $ui.U }
        default { $ui.CX + ($px - 960) * $ui.U }
    }
}
function Get-DbdY($ui, [double]$py) { $ui.Top + $py * $ui.U }
