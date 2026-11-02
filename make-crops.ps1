# Works out where the actual map (and its title) sits inside each Hens333 map
# picture, so the overlay can trim off the dark patterned background around it.
# Without this, narrow maps sat well inside their picture and looked indented
# from the screen corner. Writes crops.json: file name -> [x, y, w, h] as
# fractions of the picture. Run again after downloading new maps.
Add-Type -AssemblyName System.Drawing
$root = $PSScriptRoot
$out = [ordered]@{}
foreach ($f in Get-ChildItem (Join-Path $root 'maps') -File -Include *.png, *.jpg -Recurse) {
    $b = [System.Drawing.Bitmap]::FromFile($f.FullName); $w = $b.Width; $h = $b.Height
    $bd = $b.LockBits((New-Object System.Drawing.Rectangle 0, 0, $w, $h), 'ReadOnly', [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $buf = New-Object byte[] ($bd.Stride * $h)
    [Runtime.InteropServices.Marshal]::Copy($bd.Scan0, $buf, 0, $buf.Length); $b.UnlockBits($bd)
    $minX = $w; $minY = $h; $maxX = -1; $maxY = -1
    # background ~ RGB sum 150, its "+" marks ~ 300; map ~ 520, text ~ 765
    for ($y = 0; $y -lt $h; $y += 2) {
        $row = $y * $bd.Stride
        for ($x = 0; $x -lt $w; $x += 2) {
            $i = $row + $x * 4
            if (($buf[$i] + $buf[$i + 1] + $buf[$i + 2]) -gt 400) {
                if ($x -lt $minX) { $minX = $x }; if ($x -gt $maxX) { $maxX = $x }
                if ($y -lt $minY) { $minY = $y }; if ($y -gt $maxY) { $maxY = $y }
            }
        }
    }
    $b.Dispose()
    if ($maxX -lt 0) { continue }
    $pad = [int]([Math]::Min($w, $h) * 0.015)   # keep a thin dark edge
    $x0 = [Math]::Max(0, $minX - $pad); $y0 = [Math]::Max(0, $minY - $pad)
    $x1 = [Math]::Min($w, $maxX + 2 + $pad); $y1 = [Math]::Min($h, $maxY + 2 + $pad)
    $out[$f.Name] = @([Math]::Round($x0 / $w, 4), [Math]::Round($y0 / $h, 4), [Math]::Round(($x1 - $x0) / $w, 4), [Math]::Round(($y1 - $y0) / $h, 4))
}
$out | ConvertTo-Json -Depth 3 | Set-Content (Join-Path $root 'crops.json') -Encoding utf8
"crops.json: $($out.Count) maps"
