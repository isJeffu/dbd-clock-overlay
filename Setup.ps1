# Downloads the clock-callout map images from Hens333's site (hens333.com/callouts,
# images made by Lethia) into the "maps" folder, and converts them to PNG.
# The images are not included in this package because they aren't ours to share -
# each person downloads them from the original site. Run it again to refresh them.

# -Installer: run by Install.ps1, which prints its own "what next"
# -MissingOnly: only fetch maps not downloaded yet (updates)
param([switch]$Installer, [switch]$MissingOnly)
Add-Type -AssemblyName PresentationCore, WindowsBase, System.Drawing
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$maps = Get-Content (Join-Path $root 'maps.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$out = Join-Path $root 'maps'
New-Item -ItemType Directory -Force $out | Out-Null
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('dbd-clock-maps-' + [guid]::NewGuid())
New-Item -ItemType Directory -Force $tmp | Out-Null
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Save-Png([System.Windows.Media.Imaging.BitmapSource]$img, [string]$path) {
    $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($img))
    $fs = [IO.File]::Create($path); $enc.Save($fs); $fs.Close()
}

$done = 0; $failed = @()
foreach ($m in $maps) {
    if ($MissingOnly -and (Test-Path (Join-Path $out $m.file))) { $done++; continue }
    Write-Host ("[{0}/{1}] {2}" -f ($done + $failed.Count + 1), $maps.Count, $m.name)
    try {
        $url = 'https://hens333.com/img/dbd/callouts/' + ((($m.path -split '/') | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/')
        $src = Join-Path $tmp ('img' + [IO.Path]::GetExtension($m.path))
        Invoke-WebRequest $url -OutFile $src -UseBasicParsing
        $dest = Join-Path $out $m.file
        if ($m.path -like '*.gif') {
            # Midwich: an animation of the two floors - put top and bottom side by side
            $gif = [System.Drawing.Image]::FromFile($src)
            $dim = New-Object System.Drawing.Imaging.FrameDimension $gif.FrameDimensionsList[0]
            $w = $gif.Width; $h = $gif.Height
            $sheet = New-Object System.Drawing.Bitmap ($w * 2), $h
            $g = [System.Drawing.Graphics]::FromImage($sheet)
            [void]$gif.SelectActiveFrame($dim, [Math]::Min(3, $gif.GetFrameCount($dim) - 1)); $g.DrawImage($gif, 0, 0, $w, $h)   # top floor
            [void]$gif.SelectActiveFrame($dim, 0);                                                $g.DrawImage($gif, $w, 0, $w, $h)  # bottom floor
            $g.Dispose(); $sheet.Save($dest, [System.Drawing.Imaging.ImageFormat]::Png); $sheet.Dispose(); $gif.Dispose()
        } else {
            $fs = [IO.File]::OpenRead($src)
            $dec = [System.Windows.Media.Imaging.BitmapDecoder]::Create($fs, 'None', 'OnLoad')
            $fs.Close()
            Save-Png $dec.Frames[0] $dest
        }
        $done++
    } catch {
        $failed += "$($m.name): $($_.Exception.Message)"
    }
}
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

# Perk icons (every survivor perk in perks.json, plus the killer / status ones
# the timers use), from the Dead by Daylight wiki
$iconDir = Join-Path $root 'icons'
New-Item -ItemType Directory -Force $iconDir | Out-Null
$db = Get-Content (Join-Path $root 'perks.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$iconFiles = @($db.perks | ForEach-Object { $_.file }) + @($db.killer | ForEach-Object { $_.file }) + @($db.basekit | ForEach-Object { $_.file }) + @('IconStatusEffects_exhausted.png')
Write-Host "Downloading $($iconFiles.Count) perk icons..."
$iconsOk = 0
foreach ($icon in $iconFiles) {
    $dest = Join-Path $iconDir $icon
    if (Test-Path $dest) { $iconsOk++; continue }
    try { Invoke-WebRequest "https://deadbydaylight.wiki.gg/images/$icon" -OutFile $dest -UseBasicParsing; $iconsOk++ }
    catch { $failed += "icon ${icon}: $($_.Exception.Message)" }
}
Write-Host "Perk icons: $iconsOk of $($iconFiles.Count)."

Write-Host ''
Write-Host "Downloaded $done of $($maps.Count) maps."
if ($failed) {
    Write-Host 'These failed:' -ForegroundColor Yellow
    $failed | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
    if ($failed -match 'decoder|codec|component') {
        Write-Host 'If it mentions a missing decoder, install "Webp Image Extensions" from the Microsoft Store and run this again.' -ForegroundColor Yellow
    }
} elseif (-not $Installer) {
    Write-Host 'All done - now run "2 - Start overlay".' -ForegroundColor Green
}
