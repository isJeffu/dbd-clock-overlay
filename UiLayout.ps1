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

function Get-DbdUi([double]$w, [double]$h, [string]$mode = 'auto') {
    $u = [Math]::Min($w / 1920.0, $h / 1080.0)   # design px -> screen px
    $bw = 1920 * $u; $bh = 1080 * $u               # the 16:9 design area
    if ($mode -eq '16:9') { $left = ($w - $bw) / 2; $top = ($h - $bh) / 2 } else { $left = 0.0; $top = 0.0 }
    $right = if ($mode -eq '16:9') { $left + $bw } else { $w }
    @{ U = $u; Left = $left; Right = $right; Top = $top; CX = $w / 2 }
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
