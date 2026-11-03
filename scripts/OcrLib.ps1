# Screen text reading with the OCR built into Windows (no downloads, nothing
# touches the game - it only looks at a screenshot of the monitor).

Add-Type -AssemblyName System.Runtime.WindowsRuntime, System.Drawing, System.Windows.Forms
$null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.SoftwareBitmap, Windows.Foundation, ContentType = WindowsRuntime]

$script:AsTaskGeneric = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
} | Select-Object -First 1

function Wait-WinRt($op, [Type]$resultType) {
    $task = $script:AsTaskGeneric.MakeGenericMethod($resultType).Invoke($null, @($op))
    [void]$task.Wait(-1)
    $task.Result
}

$script:OcrEngine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()

Add-Type -Namespace DbdOverlay -Name Fg -MemberDefinition @'
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
[DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr h);
[DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr h, IntPtr dc);
[DllImport("gdi32.dll")] public static extern int GetDeviceCaps(IntPtr dc, int index);
public struct RECT { public int L, T, R, B; }
'@

# Approximate text search for map names the OCR slightly mangles ("COMPLE>C"
# for "COMPLEX"): smallest edit distance between the name and any part of the
# screen text (insert / delete / replace one character = 1).
if (-not ('DbdOverlay.Fuzzy' -as [type])) {
Add-Type -TypeDefinition @'
using System;
namespace DbdOverlay {
public static class Fuzzy {
    public static int BestDistance(string text, string pat) {
        int n = text.Length, m = pat.Length;
        var prev = new int[n + 1]; var cur = new int[n + 1];
        for (int i = 1; i <= m; i++) {
            cur[0] = i;
            for (int j = 1; j <= n; j++) {
                int cost = pat[i - 1] == text[j - 1] ? 0 : 1;
                cur[j] = Math.Min(Math.Min(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + cost);
            }
            var t = prev; prev = cur; cur = t;
        }
        int best = int.MaxValue;
        for (int j = 0; j <= n; j++) if (prev[j] < best) best = prev[j];
        return best;
    }
}
}
'@
}

# Real pixels per "logical" pixel (1 when this process is DPI-aware, else the
# Windows scaling factor, e.g. 1.5 at 150%)
function Get-PixelScale {
    $dc = [DbdOverlay.Fg]::GetDC([IntPtr]::Zero)
    $phys = [DbdOverlay.Fg]::GetDeviceCaps($dc, 118)   # DESKTOPHORZRES
    $log  = [DbdOverlay.Fg]::GetDeviceCaps($dc, 8)     # HORZRES
    [void][DbdOverlay.Fg]::ReleaseDC([IntPtr]::Zero, $dc)
    if ($log -gt 0 -and $phys -gt 0) { $phys / $log } else { 1.0 }
}

# The game's main window handle, or 0 when it isn't running / has no window yet
function Get-DbdWindow {
    $p = Get-Process -Name 'DeadByDaylight*' -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if ($p) { $p.MainWindowHandle } else { [IntPtr]::Zero }
}

# Picture of the game window alone (PrintWindow), used when the game is running
# but another window has the focus - e.g. you tabbed to a second monitor while
# a match loads. Only the game's own pixels are captured, never other windows.
# Returns $null when it isn't possible (no window, minimised, capture refused).
function Get-DbdWindowBitmap([System.Drawing.Rectangle]$blackout = [System.Drawing.Rectangle]::Empty) {
    $h = Get-DbdWindow
    if ($h -eq [IntPtr]::Zero -or [DbdOverlay.Fg]::IsIconic($h)) { return $null }
    $r = New-Object DbdOverlay.Fg+RECT
    if (-not [DbdOverlay.Fg]::GetWindowRect($h, [ref]$r)) { return $null }
    $scale = Get-PixelScale   # PrintWindow draws real pixels, so size the bitmap in real pixels
    $w = [int](($r.R - $r.L) * $scale); $ht = [int](($r.B - $r.T) * $scale)
    if ($w -lt 200 -or $ht -lt 200) { return $null }
    $bmp = New-Object System.Drawing.Bitmap $w, $ht
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc()
    $ok = [DbdOverlay.Fg]::PrintWindow($h, $hdc, 2)   # 2 = PW_RENDERFULLCONTENT
    $g.ReleaseHdc($hdc)
    if ($ok -and -not $blackout.IsEmpty) { $g.FillRectangle([System.Drawing.Brushes]::Black, $blackout) }
    $g.Dispose()
    if (-not $ok) { $bmp.Dispose(); return $null }
    $bmp
}

# Diagnostic: which window is in front right now ("process | title")
function Get-ForegroundInfo {
    $h = [DbdOverlay.Fg]::GetForegroundWindow()
    $procId = 0
    [void][DbdOverlay.Fg]::GetWindowThreadProcessId($h, [ref]$procId)
    $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
    $sb = New-Object System.Text.StringBuilder 256
    [void][DbdOverlay.Fg]::GetWindowText($h, $sb, 256)
    "{0} | {1} | hwnd={2}" -f $(if ($p) { $p.ProcessName } else { "pid $procId" }), $sb.ToString(), $h
}

# True when Dead by Daylight is the window in front - we only ever read the
# screen then, so nothing else on your PC gets scanned or logged
function Test-DbdInFront {
    $procId = 0
    [void][DbdOverlay.Fg]::GetWindowThreadProcessId([DbdOverlay.Fg]::GetForegroundWindow(), [ref]$procId)
    $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
    [bool]($p -and $p.ProcessName -like 'DeadByDaylight*')
}

# Returns the recognised text of a System.Drawing.Bitmap, one line per OCR line.
# The pixels are copied straight into one reused buffer per picture size (no
# 33 MB re-encoded copy per scan), so memory stays flat without forcing the
# garbage collector - a forced collection freezes the whole overlay for a moment.
$script:PixelBuffers = @{}
function Read-BitmapText([System.Drawing.Bitmap]$bmp) {
    $w = $bmp.Width; $h = $bmp.Height; $len = $w * $h * 4
    $buf = $script:PixelBuffers[$len]
    if (-not $buf) { $buf = New-Object byte[] $len; $script:PixelBuffers[$len] = $buf }
    $data = $bmp.LockBits((New-Object System.Drawing.Rectangle 0, 0, $w, $h), 'ReadOnly', [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        # rows are copied one by one in case the bitmap pads them
        if ($data.Stride -eq $w * 4) { [Runtime.InteropServices.Marshal]::Copy($data.Scan0, $buf, 0, $len) }
        else { for ($y = 0; $y -lt $h; $y++) { [Runtime.InteropServices.Marshal]::Copy([IntPtr]($data.Scan0.ToInt64() + $y * $data.Stride), $buf, $y * $w * 4, $w * 4) } }
    } finally { $bmp.UnlockBits($data) }
    $soft = New-Object Windows.Graphics.Imaging.SoftwareBitmap ([Windows.Graphics.Imaging.BitmapPixelFormat]::Bgra8), $w, $h, ([Windows.Graphics.Imaging.BitmapAlphaMode]::Premultiplied)
    try {
        $soft.CopyFromBuffer([System.Runtime.InteropServices.WindowsRuntime.WindowsRuntimeBufferExtensions]::AsBuffer($buf))
        $result = Wait-WinRt ($script:OcrEngine.RecognizeAsync($soft)) ([Windows.Media.Ocr.OcrResult])
    } finally { $soft.Dispose() }
    ($result.Lines | ForEach-Object { $_.Text }) -join "`n"
}

# Screenshot of the primary monitor (physical pixels), optionally blacking out
# a rectangle (the overlay itself, so it never reads its own map title)
function Get-ScreenBitmap([System.Drawing.Rectangle]$blackout = [System.Drawing.Rectangle]::Empty) {
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
    if (-not $blackout.IsEmpty) { $g.FillRectangle([System.Drawing.Brushes]::Black, $blackout) }
    $g.Dispose()
    $bmp
}

# Is the loadout panel open? Reads only its "LOADOUT" title (top left, under
# the character name; pinned to the LEFT edge, UiLayout.ps1) - tens of ms
# instead of a full-screen read, so the perk roulette button can follow the
# panel quickly. Returns 'survivor' / 'killer', or $null when it isn't open.
# $from = a screenshot to read instead of the screen (tests).
function Test-LoadoutTitle([System.Drawing.Bitmap]$from, [string]$layout = 'auto', [double]$scale = 0) {
    $b = if ($from) { New-Object System.Drawing.Rectangle 0, 0, $from.Width, $from.Height } else { [System.Windows.Forms.Screen]::PrimaryScreen.Bounds }
    if ($scale -le 0) { $scale = (Get-DbdScales).Menu }   # DbD's Menu scale setting
    $ui = Get-DbdUi $b.Width $b.Height $layout $scale; $u = $ui.U
    $src = New-Object System.Drawing.Rectangle ($b.X + [int](Get-DbdX $ui 360 'left')), ($b.Y + [int](Get-DbdY $ui 50)), ([int](170 * $u)), ([int](58 * $u))
    # resampled to 3x its 1080p size: OCR reads text ~40 px tall best
    $big = New-Object System.Drawing.Bitmap 510, 174
    $g = [System.Drawing.Graphics]::FromImage($big)
    try {
        $g.InterpolationMode = 'HighQualityBicubic'
        if ($from) { $g.DrawImage($from, (New-Object System.Drawing.Rectangle 0, 0, 510, 174), $src, 'Pixel') }
        else {
            $shot = New-Object System.Drawing.Bitmap $src.Width, $src.Height
            $gs = [System.Drawing.Graphics]::FromImage($shot); $gs.CopyFromScreen($src.Location, [System.Drawing.Point]::Empty, $src.Size); $gs.Dispose()
            $g.DrawImage($shot, 0, 0, 510, 174); $shot.Dispose()
        }
    } finally { $g.Dispose() }
    try { $t = Read-BitmapText $big } finally { $big.Dispose() }
    $key = ' ' + (ConvertTo-MatchKey ($t -replace "`n", ' ')) + ' '
    if (-not $key.Contains(' LOADOUT ')) { return $null }
    # Who you play: the first slot's label says ITEM (survivor) or POWER (killer),
    # 1080p (300,165) 130x34. (Killer names don't always start with "THE" - a
    # killer showed as "MINA", 3 Nov - so the name is only the fallback.)
    $lab = New-Object System.Drawing.Rectangle ([int](Get-DbdX $ui 300 'left')), ([int](Get-DbdY $ui 165)), ([int](130 * $u)), ([int](34 * $u))
    $big = New-Object System.Drawing.Bitmap 390, 102
    $g = [System.Drawing.Graphics]::FromImage($big)
    try {
        $g.InterpolationMode = 'HighQualityBicubic'
        if ($from) { $g.DrawImage($from, (New-Object System.Drawing.Rectangle 0, 0, 390, 102), $lab, 'Pixel') }
        else {
            $lab.X += $b.X; $lab.Y += $b.Y
            $shot = New-Object System.Drawing.Bitmap $lab.Width, $lab.Height
            $gs = [System.Drawing.Graphics]::FromImage($shot); $gs.CopyFromScreen($lab.Location, [System.Drawing.Point]::Empty, $lab.Size); $gs.Dispose()
            $g.DrawImage($shot, 0, 0, 390, 102); $shot.Dispose()
        }
    } finally { $g.Dispose() }
    try { $lt = ' ' + (ConvertTo-MatchKey ((Read-BitmapText $big) -replace "`n", ' ')) + ' ' } finally { $big.Dispose() }
    if ($lt -match ' P?OWER ') { return 'killer' }
    if ($lt.Contains(' ITEM ')) { return 'survivor' }
    if ($key -match ' THE [A-Z]') { 'killer' } else { 'survivor' }
}
# The same question from a full-screen read: a killer's loadout has a POWER slot
# where a survivor's has ITEM
function Get-LoadoutRole([string]$text) {
    $key = ' ' + (ConvertTo-MatchKey ($text -replace "`n", ' ')) + ' '
    # (OCR sometimes drops the P: "OWER"; or misses the slot labels, but still reads
    # the name over the title: "THE TERRIFIER 100 LOADOUT")
    if (($key -match ' P?OWER ' -and -not $key.Contains(' ITEM ')) -or $key -match ' THE [A-Z]+( [A-Z]+)? (\d+ )?LOADOUT ') { 'killer' } else { 'survivor' }
}

function ConvertTo-MatchKey([string]$s) {
    # Drop accents first, so "LÉRY'S" becomes "LERYS" rather than "LRYS"
    $plain = -join ($s.Normalize([Text.NormalizationForm]::FormD).ToCharArray() |
        Where-Object { [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark' })
    $k = (($plain.ToUpperInvariant() -replace "[^A-Z0-9 ]", '') -replace '\s+', ' ').Trim()
    # Roman numerals as digits, so "PRESCHOOL 3" and "PRESCHOOL III" both match
    $roman = [ordered]@{ 'III' = '3'; 'II' = '2'; 'IV' = '4'; 'V' = '5'; 'I' = '1' }
    foreach ($r in $roman.Keys) { $k = $k -replace "\b$r\b", $roman[$r] }
    $k
}

# Words seen on the lobby, menus and the end-of-match screen but not on the
# in-match HUD or the in-match Esc screen (that one has QUESTS and MATCH DETAILS,
# so those are left out). Two or more of them on screen = we're out of the trial.
$script:MenuWords = @('READY', 'FIND MATCH', 'CONTINUE', 'BLOODWEB', 'STORE', 'ARCHIVES',
    'LOADOUT', 'CHARACTER INFO', 'CUSTOMIZATION', 'SCOREBOARD', 'EMBLEMS', 'RIFT', 'PLAY AS SURVIVOR',
    'PLAY AS KILLER', 'LEAVE LOBBY', 'BACK TO LOBBY', 'PRESTIGE', 'SHRINE OF SECRETS',
    # seen in the log on the real end screen and lobby (17 Oct)
    'SPECTATE', 'MATCH RESULT', 'BLOODPOINTS EARNED', 'LEAVE PARTY', 'PLAY', 'ENTER TEXT', 'IN A MATCH',
    # report-player window on the end screen
    'SELECT A CATEGORY', 'SUBMIT', 'REPORT',
    # loadout panel only: with just LOADOUT read (chat box OCR'd as "Entenext...",
    # READY turned into CANCEL) it counted as in-match, and its SEARCH box as a
    # HUD prompt - that cleared the roulette (Consy's log, 2 Nov)
    'PRESET', 'ADD-ONS', 'INVENTORY/PERKS')

function Get-MenuWordHits([string]$text) {
    $key = ' ' + (ConvertTo-MatchKey ($text -replace "`n", ' ')) + ' '
    @($script:MenuWords | Where-Object { $key.Contains(' ' + (ConvertTo-MatchKey $_) + ' ') })
}

# Prompts and status effects that only show on the in-match HUD (survivor and
# killer). Any one of them, when no menu words are on screen = we're in a trial.
$script:HudWords = @('REPAIR', 'REPAIRS', 'OPEN ESCAPE', 'SKILL CHECK', 'GOOD SKILL CHECK', 'GREAT SKILL CHECK',
    'UNLOCKING', 'HEAL', 'HEALING', 'UNHOOK', 'CLEANSE', 'BLESS', 'SABOTAGE', 'SEARCH', 'HIDE',
    'HINDERED', 'EXHAUSTED', 'INCAPACITATED', 'ENDURANCE', 'HASTE', 'BLINDNESS', 'BROKEN', 'OBLIVIOUS',
    'PICK UP', 'HOOK', 'DAMAGE GENERATOR', 'BREAK', 'KICK', 'PULL DOWN', 'SHATTER', 'WIGGLE',
    'EXIT GATE', 'HATCH', 'TOTEM', 'KILLER POWER', 'KILLERS POWER')

function Get-HudWordHits([string]$text) {
    $key = ' ' + (ConvertTo-MatchKey ($text -replace "`n", ' ')) + ' '
    # Loading-screen tips ("...BY DAYLIGHT" banner) mention skill checks, unhooking etc.
    if ($key.Contains(' BY DAYLIGHT ')) { return @() }
    @($script:HudWords | Where-Object { $key.Contains(' ' + (ConvertTo-MatchKey $_) + ' ') })
}

# Score pop-ups for your own actions:
#   "HOOK RESCUE" (+1000 / SAFE HOOK RESCUE)  = you unhooked someone
#   "CHASED" / "ESCAPED"                      = a chase you were in has just ended
function Get-ScoreEvents([string]$text) {
    $key = ' ' + (ConvertTo-MatchKey ($text -replace "`n", ' ')) + ' '
    # Only the unhook itself. "SAFE HOOK RESCUE" (~15 s later, the rescued survivor
    # wasn't hit) and "LATE HOOK RESCUE" are follow-up pop-ups for the same unhook
    # and must not restart the timers. OCR sometimes glues a letter on ("USAFE").
    $rescue = $false
    foreach ($m in [regex]::Matches($key, '(\S*) HOOK RESCUE ')) {
        if ($m.Groups[1].Value -notmatch '(SAFE|LATE)$') { $rescue = $true }
    }
    @{
        Rescue   = $rescue
        # You were just unhooked: the status strip names the basekit effects
        # ("HASTE ENDURANCE", often with the rescuer's perk, e.g. WE'LL MAKE IT)
        Unhooked = (-not $rescue) -and $key.Contains(' ENDURANCE ') -and $key.Contains(' HASTE ') -and -not $key.Contains(' LOADOUT ') -and -not $key.Contains(' PRESET ')
        ChaseEnd = $key.Contains(' CHASED ') -or $key.Contains(' ESCAPED ')
        # Picked up by the killer (WIGGLE prompt): the camera no longer follows
        # your facing, so the compass heading is void from here. Loading-screen
        # tips mention wiggling too - ignore those.
        Carried  = $key.Contains(' WIGGLE') -and -not $key.Contains(' BY DAYLIGHT ')
        # In-match Esc / TAB screens: the mouse moves a cursor there, not the camera
        MenuOpen = $key.Contains(' MATCH DETAILS ') -or ($key.Contains(' PLAYERS ') -and $key.Contains(' QUESTS '))
        # Your match is over (died / escaped): the camera is no longer yours
        Dead     = $key.Contains(' MATCH RESULT ')
    }
}

# Endgame Collapse bar (top of the screen, once a gate is opened). Measured on a
# 3840x2160 screen (19 Oct): the track runs from x 734 to ~3095, rows 69-86. The
# fill drains right to left; it is grey-white (~118) or orange (195/105/0), the
# drained part is dark blue-grey. Returns @{ Frac = 0..1; Orange = $true/$false }
# or $null when no bar is there. Pixels only, no OCR.
# In 1080p design pixels the track is x 367-1548 (pinned to the MIDDLE of the
# screen, UiLayout.ps1), rows 37 and 41 - so it's found on ultrawide too.
function Get-CollapseBar([System.Drawing.Bitmap]$bmp, [string]$layout = 'auto', [double]$scale = 0) {
    if ($scale -le 0) { $scale = (Get-DbdScales).Hud }   # the bar is HUD: DbD's HUD scale setting
    $ui = Get-DbdUi $bmp.Width $bmp.Height $layout $scale
    $x0 = [Math]::Max(0, [int](Get-DbdX $ui 367.1 'center')); $x1 = [Math]::Min($bmp.Width - 1, [int](Get-DbdX $ui 1547.5 'center'))
    $ya = [int](Get-DbdY $ui 37.04); $yb = [int](Get-DbdY $ui 41.04)
    $step = [Math]::Max(1, [int](1.5 * $ui.U))
    $cls = New-Object System.Text.StringBuilder
    $orange = 0
    for ($x = $x0; $x -le $x1; $x += $step) {
        $c = $bmp.GetPixel($x, $yb); $a = $bmp.GetPixel($x, $ya)
        $r = ($c.R + $a.R) / 2; $g = ($c.G + $a.G) / 2; $b = ($c.B + $a.B) / 2
        $mx = [Math]::Max($r, [Math]::Max($g, $b)); $mn = [Math]::Min($r, [Math]::Min($g, $b))
        if ($r -ge 120 -and $b -le 45 -and ($r - $b) -ge 100 -and $g -le 0.8 * $r) { [void]$cls.Append('F'); $orange++ }
        elseif ($mx -ge 85 -and $mx -le 235 -and ($mx - $mn) -lt 14) { [void]$cls.Append('F') }
        elseif ($mx -lt 95 -and $b -ge $r - 5) { [void]$cls.Append('.') }
        elseif ($r -ge 50 -and $r -lt 160 -and $b -le 35 -and $g -lt 0.6 * $r) { [void]$cls.Append('r') }   # dark-red trail just drained (orange phase)
        else { [void]$cls.Append('?') }
    }
    $s = $cls.ToString(); $n = $s.Length
    # The fill starts at the left end; a few odd samples inside it are allowed
    # (a lone dark-red 'r' inside the fill is a blended pixel, not the trail - seen at 85% HUD scale)
    $m = [regex]::Match($s, '^(?:F|[.?r]{1,4}(?=F))*')
    $fillEnd = $m.Length
    $fill = $s.Substring(0, $fillEnd); $rest = $s.Substring($fillEnd)
    # skip the bright marker at the fill's edge, the rest must be dark track
    $tail = if ($rest.Length -gt 12) { $rest.Substring(12) } else { '' }
    $fillOk = $fillEnd -eq 0 -or (($fill.ToCharArray() | Where-Object { $_ -eq 'F' }).Count -ge 0.9 * $fillEnd)
    $trackOk = $tail.Length -eq 0 -or (($tail.ToCharArray() | Where-Object { $_ -eq '.' -or $_ -eq 'r' }).Count -ge 0.8 * $tail.Length)
    # both parts must look right, and there must be some fill: a dark blue scene
    # alone looks like an empty track (an empty bar = collapse over anyway)
    if (-not ($fillOk -and $trackOk) -or $fillEnd -lt 10) { return $null }
    @{ Frac = [Math]::Min(1.0, $fillEnd / ($n - 1)); Orange = ($orange -gt 0.5 * [Math]::Max(1, $fillEnd)) }
}

# Status effects named in the HUD strip (bottom right), with whatever else is
# on the same line as the likely cause ("KILLERS POWER", a perk name, an
# event item). One entry per effect found.
$script:StatusEffects = @('OBLIVIOUS', 'EXHAUSTED', 'HASTE', 'ENDURANCE', 'HINDERED', 'EXPOSED', 'BROKEN', 'BLINDNESS', 'DEEP WOUND',
    'MANGLED', 'HEMORRHAGE', 'INCAPACITATED', 'CURSED', 'BLESSED', 'UNDETECTABLE', 'ELUSIVE', 'LUCK', 'SLEEP', 'MADNESS', 'TORMENT', 'VULNERABLE')
function Get-StatusEffects([string]$text) {
    $out = @()
    foreach ($line in ($text -split "`n")) {
        $lk = ' ' + (ConvertTo-MatchKey $line) + ' '
        if ($lk.Contains(' BY DAYLIGHT ')) { continue }
        $found = @($script:StatusEffects | Where-Object { $lk.Contains(' ' + $_ + ' ') })
        if (-not $found.Count) { continue }
        $rest = $lk
        foreach ($f in $found) { $rest = $rest -replace (' ' + $f + ' '), ' ' }
        $rest = ($rest -replace '\s+', ' ').Trim()
        if ($rest.Length -gt 28) { $rest = $rest.Substring(0, 28) }
        foreach ($f in $found) { $out += @{ Effect = $f; Cause = $rest } }
    }
    $out
}

# Finds the map whose name appears in the text. Longest name wins, so
# "COAL TOWER II" beats "COAL TOWER". Roman numerals must end the word.
function Find-MapInText([string]$text, $maps) {
    $key = ' ' + (ConvertTo-MatchKey ($text -replace "`n", ' ')) + ' '
    $best = $null
    foreach ($m in $maps) {
        # 'The Game' turns up in ordinary sentences - only trust its realm name for that one
        $names = if ($m.nameIsTooCommon) { @($m.aliases) } else { @($m.name) + @($m.aliases) }
        foreach ($n in $names) {
            if (-not $n) { continue }
            $nk = ' ' + (ConvertTo-MatchKey $n) + ' '
            if ($key.Contains($nk) -and (-not $best -or $nk.Length -gt $best.Len)) {
                $best = @{ Map = $m; Len = $nk.Length }
            }
        }
    }
    if ($best) { return $best.Map }
    # No exact hit: allow 1 wrong character per 10 in longer names (OCR slips
    # like "COMPLE>C"), taking the closest match. Short names stay exact.
    $bestRatio = 1.0
    foreach ($m in $maps) {
        $names = if ($m.nameIsTooCommon) { @($m.aliases) } else { @($m.name) + @($m.aliases) }
        foreach ($n in $names) {
            if (-not $n) { continue }
            $nk = ' ' + (ConvertTo-MatchKey $n) + ' '
            $len = $nk.Length - 2
            if ($len -lt 10) { continue }
            $d = [DbdOverlay.Fuzzy]::BestDistance($key, $nk)
            $ratio = $d / $len
            if ($d -le [Math]::Floor($len / 10) -and $ratio -lt $bestRatio) { $bestRatio = $ratio; $best = $m }
        }
    }
    $best
}
