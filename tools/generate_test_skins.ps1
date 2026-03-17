$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$magnumDir = Join-Path $root "assets/visual/magnum"
$bulletDir = Join-Path $root "assets/visual/Bullet"

New-Item -ItemType Directory -Force -Path $magnumDir | Out-Null
New-Item -ItemType Directory -Force -Path $bulletDir | Out-Null

function Hex([string]$h) {
    return [System.Drawing.ColorTranslator]::FromHtml($h)
}

function New-Canvas([int]$w, [int]$h, [string]$hex) {
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.Clear((Hex $hex))
    return @($bmp, $g)
}

function Save-Close($bmp, $g, [string]$path) {
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose()
    $bmp.Dispose()
}

function Draw-NeonGrid($g, [int]$w, [int]$h, [string]$base, [string]$line, [int]$step, [int]$thickness) {
    if ($base -ne "") {
        $g.Clear((Hex $base))
    }
    $pen = New-Object System.Drawing.Pen((Hex $line), $thickness)
    for ($x = 0; $x -lt $w; $x += $step) {
        $g.DrawLine($pen, $x, 0, $x, $h)
    }
    for ($y = 0; $y -lt $h; $y += $step) {
        $g.DrawLine($pen, 0, $y, $w, $y)
    }
    $pen.Dispose()
}

function Draw-DiagonalBars($g, [int]$w, [int]$h, [string]$c1, [string]$c2, [int]$band) {
    $b1 = New-Object System.Drawing.SolidBrush((Hex $c1))
    $b2 = New-Object System.Drawing.SolidBrush((Hex $c2))
    for ($i = -$h; $i -lt $w; $i += $band) {
        $pts = [System.Drawing.Point[]]@(
            (New-Object System.Drawing.Point($i, 0)),
            (New-Object System.Drawing.Point([int]($i + $band / 2), 0)),
            (New-Object System.Drawing.Point([int]($i + $h + $band / 2), $h)),
            (New-Object System.Drawing.Point([int]($i + $h), $h))
        )
        if (([int](($i + $h) / $band)) % 2 -eq 0) {
            $g.FillPolygon($b1, $pts)
        }
        else {
            $g.FillPolygon($b2, $pts)
        }
    }
    $b1.Dispose()
    $b2.Dispose()
}

function Draw-HexNoise($g, [int]$w, [int]$h, [string]$hex, [int]$count, [int]$size, [int]$seed) {
    $pen = New-Object System.Drawing.Pen((Hex $hex), 2)
    $rnd = New-Object System.Random($seed)
    for ($i = 0; $i -lt $count; $i++) {
        $cx = $rnd.Next(0, $w)
        $cy = $rnd.Next(0, $h)
        $s = $rnd.Next([int]($size * 0.5), $size)
        $pts = New-Object "System.Collections.Generic.List[System.Drawing.Point]"
        for ($k = 0; $k -lt 6; $k++) {
            $a = [Math]::PI / 3 * $k
            $x = [int]($cx + [Math]::Cos($a) * $s)
            $y = [int]($cy + [Math]::Sin($a) * $s)
            $pts.Add((New-Object System.Drawing.Point($x, $y)))
        }
        $g.DrawPolygon($pen, $pts.ToArray())
    }
    $pen.Dispose()
}

function Draw-Rings($g, [int]$w, [int]$h, [string]$hex, [int]$count, [int]$thickness) {
    $pen = New-Object System.Drawing.Pen((Hex $hex), $thickness)
    $cx = [int]($w / 2)
    $cy = [int]($h / 2)
    $maxR = [Math]::Min($w, $h) - 20
    for ($i = 1; $i -le $count; $i++) {
        $r = [int](($maxR / $count) * $i)
        $g.DrawEllipse($pen, [int]($cx - $r / 2), [int]($cy - $r / 2), $r, $r)
    }
    $pen.Dispose()
}

# Magnum skins (1024)
$set = New-Canvas 1024 1024 "#070815"; $bmp = $set[0]; $g = $set[1]
Draw-NeonGrid $g 1024 1024 "#070815" "#ff2a8f" 64 2
Draw-DiagonalBars $g 1024 1024 "#1a0d2a" "#0e1026" 140
Draw-HexNoise $g 1024 1024 "#2de2e6" 45 26 420
Save-Close $bmp $g (Join-Path $magnumDir "test_skin_magnum_neon_grid.png")

$set = New-Canvas 1024 1024 "#0a0e1f"; $bmp = $set[0]; $g = $set[1]
Draw-DiagonalBars $g 1024 1024 "#14213d" "#0f172a" 120
Draw-NeonGrid $g 1024 1024 "" "#49f6ff" 96 3
Draw-Rings $g 1024 1024 "#ff3d9e" 18 2
Save-Close $bmp $g (Join-Path $magnumDir "test_skin_magnum_cyber_rings.png")

$set = New-Canvas 1024 1024 "#101010"; $bmp = $set[0]; $g = $set[1]
Draw-DiagonalBars $g 1024 1024 "#1f2937" "#0b1220" 90
Draw-HexNoise $g 1024 1024 "#7df9ff" 70 18 421
Draw-NeonGrid $g 1024 1024 "" "#f72585" 128 2
Save-Close $bmp $g (Join-Path $magnumDir "test_skin_magnum_dark_hextech.png")

$set = New-Canvas 1024 1024 "#0b0614"; $bmp = $set[0]; $g = $set[1]
Draw-Rings $g 1024 1024 "#9d4edd" 26 3
Draw-DiagonalBars $g 1024 1024 "#2b0b3f" "#130a24" 110
Draw-NeonGrid $g 1024 1024 "" "#00f5d4" 80 1
Save-Close $bmp $g (Join-Path $magnumDir "test_skin_magnum_void_circuit.png")

# Bullet skins (512)
$set = New-Canvas 512 512 "#0b0f1c"; $bmp = $set[0]; $g = $set[1]
Draw-NeonGrid $g 512 512 "#0b0f1c" "#25f4ee" 32 1
Draw-Rings $g 512 512 "#ff2a8f" 14 2
Save-Close $bmp $g (Join-Path $bulletDir "test_skin_bullet_neon_core.png")

$set = New-Canvas 512 512 "#18181b"; $bmp = $set[0]; $g = $set[1]
Draw-DiagonalBars $g 512 512 "#3f3f46" "#111827" 44
Draw-HexNoise $g 512 512 "#a3e635" 24 10 422
Save-Close $bmp $g (Join-Path $bulletDir "test_skin_bullet_toxic_hex.png")

$set = New-Canvas 512 512 "#14091f"; $bmp = $set[0]; $g = $set[1]
Draw-Rings $g 512 512 "#fb7185" 12 2
Draw-NeonGrid $g 512 512 "" "#67e8f9" 48 1
Save-Close $bmp $g (Join-Path $bulletDir "test_skin_bullet_pulsewave.png")

$set = New-Canvas 512 512 "#121212"; $bmp = $set[0]; $g = $set[1]
Draw-DiagonalBars $g 512 512 "#2a2a2a" "#0f172a" 36
Draw-NeonGrid $g 512 512 "" "#facc15" 64 1
Save-Close $bmp $g (Join-Path $bulletDir "test_skin_bullet_tracer_stripe.png")

Write-Output "Generated 8 test skins (4 magnum, 4 bullet)."