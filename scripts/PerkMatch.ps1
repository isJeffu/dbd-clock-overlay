# Perk icon matching: works out which perks are in the HUD diamonds by comparing
# each diamond's white glyph against the wiki icons in "icons" (their alpha
# channel is the glyph shape). Pure image comparison on a screenshot - it
# never touches the game. Dot-source this, then call Find-PerksInBitmap.
#
# Method: brightness of the diamond (darkest colour channel, so the purple
# tint drops out), masked to the diamond, shrunk to a 32x32 grid, compared by
# normalised correlation with each icon's alpha shrunk the same way. Several
# glyph sizes and small position offsets are tried; the best score wins.

Add-Type -AssemblyName System.Drawing
if (-not ('PerkMatcher' -as [type])) {
Add-Type -ReferencedAssemblies System.Drawing @"
using System; using System.Drawing; using System.Drawing.Imaging; using System.Runtime.InteropServices;
public static class PerkMatcher {
    // Brightness (darkest channel) of a square region, -1 outside the inscribed diamond
    public static float[] Region(Bitmap b, int cx, int cy, int half) {
        var r = new Rectangle(cx - half, cy - half, 2 * half, 2 * half);
        var bd = b.LockBits(r, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        var bytes = new byte[bd.Stride * r.Height]; Marshal.Copy(bd.Scan0, bytes, 0, bytes.Length); b.UnlockBits(bd);
        int w = r.Width; var g = new float[w * w];
        for (int y = 0; y < w; y++) for (int x = 0; x < w; x++) {
            int i = y * bd.Stride + x * 4;
            float v = Math.Min(bytes[i], Math.Min(bytes[i + 1], bytes[i + 2])) / 255f;
            bool inside = Math.Abs(x - half) + Math.Abs(y - half) < half * 0.92;
            g[y * w + x] = inside ? v : -1f;
        }
        return g;
    }
    public static float[] IconAlpha(Bitmap icon, int size) {
        using (var s = new Bitmap(size, size, PixelFormat.Format32bppArgb)) using (var gr = Graphics.FromImage(s)) {
            gr.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic; gr.DrawImage(icon, 0, 0, size, size);
            var bd = s.LockBits(new Rectangle(0, 0, size, size), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            var bytes = new byte[bd.Stride * size]; Marshal.Copy(bd.Scan0, bytes, 0, bytes.Length); s.UnlockBits(bd);
            var a = new float[size * size];
            for (int y = 0; y < size; y++) for (int x = 0; x < size; x++) a[y * size + x] = bytes[y * bd.Stride + x * 4 + 3] / 255f;
            return a;
        }
    }
    // Average-pool a w x w grid to n x n, ignoring -1 cells
    public static float[] Down(float[] g, int w, int n) {
        var o = new float[n * n];
        for (int oy = 0; oy < n; oy++) for (int ox = 0; ox < n; ox++) {
            int x0 = ox * w / n, x1 = Math.Max(x0 + 1, (ox + 1) * w / n), y0 = oy * w / n, y1 = Math.Max(y0 + 1, (oy + 1) * w / n); double s = 0; int c = 0;
            for (int y = y0; y < y1; y++) for (int x = x0; x < x1; x++) { float v = g[y * w + x]; if (v >= 0) { s += v; c++; } }
            o[oy * n + ox] = c > 0 ? (float)(s / c) : -1f;
        }
        return o;
    }
    // Normalised cross-correlation over cells valid in both
    public static float Ncc(float[] a, float[] b) {
        double ma = 0, mb = 0; int c = 0;
        for (int i = 0; i < a.Length; i++) if (a[i] >= 0 && b[i] >= 0) { ma += a[i]; mb += b[i]; c++; }
        if (c == 0) return -1; ma /= c; mb /= c;
        double dot = 0, sa = 0, sb = 0;
        for (int i = 0; i < a.Length; i++) if (a[i] >= 0 && b[i] >= 0) { double da = a[i] - ma, db = b[i] - mb; dot += da * db; sa += da * da; sb += db * db; }
        return (float)(dot / (Math.Sqrt(sa * sb) + 1e-9));
    }
}
"@
}

$script:perkGrid = 32
$script:perkTemplates = @{}

# Every icon as 32x32 shape grids, drawn at a few glyph sizes inside a box the
# size of the diamond (so the mask stays fixed while the glyph size varies).
# Cached per box size.
function Get-PerkTemplates([string]$iconDir, $perks, [int]$box) {
    if ($script:perkTemplates.ContainsKey($box)) { return $script:perkTemplates[$box] }
    $n = $script:perkGrid
    $sizes = @([int]($box * 0.76), [int]($box * 0.84), [int]($box * 0.91), [int]($box * 0.98))
    $list = New-Object System.Collections.ArrayList
    foreach ($p in $perks) {
        $path = Join-Path $iconDir $p.file
        if (-not (Test-Path $path)) { continue }
        $icon = [System.Drawing.Bitmap]::FromFile($path)
        $fs = foreach ($s in $sizes) {
            $pad = New-Object System.Drawing.Bitmap $box, $box, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $g = [System.Drawing.Graphics]::FromImage($pad)
            $g.InterpolationMode = 'HighQualityBicubic'
            $g.DrawImage($icon, [int](($box - $s) / 2), [int](($box - $s) / 2), $s, $s)
            $g.Dispose()
            $f = [PerkMatcher]::Down([PerkMatcher]::IconAlpha($pad, $box), $box, $n)
            $pad.Dispose()
            ,$f
        }
        $icon.Dispose()
        [void]$list.Add(@{ Name = $p.name; Fs = $fs })
    }
    $script:perkTemplates[$box] = $list
    $list
}

# $centers: diamond centres (@{X;Y}) in the bitmap. $half: half the diamond's
# diagonal in pixels (55 at 2160p). Returns one entry per slot with the top 3
# names and scores.
function Find-PerksInBitmap([System.Drawing.Bitmap]$bmp, $centers, [string]$iconDir, $perks, [int]$half = 55, [int[]]$jitter = @(-4, -2, 0, 2, 4)) {
    $n = $script:perkGrid
    $box = 2 * $half
    $templates = Get-PerkTemplates $iconDir $perks $box
    $results = @()
    foreach ($c in $centers) {
        $scores = @{}
        foreach ($dx in $jitter) { foreach ($dy in $jitter) {
            $cx = [int]$c.X + $dx; $cy = [int]$c.Y + $dy
            if ($cx - $half -lt 0 -or $cy - $half -lt 0 -or $cx + $half -gt $bmp.Width -or $cy + $half -gt $bmp.Height) { continue }
            $cf = [PerkMatcher]::Down([PerkMatcher]::Region($bmp, $cx, $cy, $half), $box, $n)
            foreach ($t in $templates) {
                foreach ($f in $t.Fs) {
                    $v = [PerkMatcher]::Ncc($cf, $f)
                    if (-not $scores.ContainsKey($t.Name) -or $v -gt $scores[$t.Name]) { $scores[$t.Name] = $v }
                }
            }
        } }
        $top = @($scores.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 3)
        if ($top.Count) {
            $results += @{ Name = $top[0].Key; Score = [Math]::Round($top[0].Value, 3); Second = $top[1].Key; SecondScore = [Math]::Round($top[1].Value, 3); Third = $top[2].Key; ThirdScore = [Math]::Round($top[2].Value, 3) }
        } else { $results += @{ Name = $null; Score = 0 } }
    }
    $results
}
