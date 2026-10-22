# Genera windows\runner\resources\app_icon.ico: destello naranja + termómetro.
# Se dibuja en una cuadrícula de 256 unidades y se renderiza en cada tamaño.
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
$out = Join-Path $root 'windows\runner\resources\app_icon.ico'

function Color($hex) { [System.Drawing.ColorTranslator]::FromHtml($hex) }

function RoundRect($x, $y, $w, $h, $r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = 2 * $r
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    $p
}

function Render([int]$size) {
    $bmp = New-Object System.Drawing.Bitmap $size, $size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.ScaleTransform($size / 256, $size / 256)

    # Fondo
    $g.FillPath((New-Object System.Drawing.SolidBrush (Color '#262624')), (RoundRect 8 8 240 240 48))

    # Destello: 4 puntas largas y 4 cortas
    $cx = 92; $cy = 128
    $pts = for ($i = 0; $i -lt 16; $i++) {
        $a = [Math]::PI * $i / 8 - [Math]::PI / 2
        $r = if ($i % 2) { 19 } elseif ($i % 4 -eq 0) { 66 } else { 36 }
        New-Object System.Drawing.PointF ($cx + $r * [Math]::Cos($a)), ($cy + $r * [Math]::Sin($a))
    }
    $g.FillPolygon((New-Object System.Drawing.SolidBrush (Color '#D97757')), [System.Drawing.PointF[]]$pts)

    # Termómetro: tubo + bulbo blancos, mercurio verde
    $white = New-Object System.Drawing.SolidBrush (Color '#F5F4EE')
    $merc = New-Object System.Drawing.SolidBrush (Color '#4ADE80')
    $g.FillPath($white, (RoundRect 168 46 30 130 15))
    $g.FillEllipse($white, 155, 160, 56, 56)
    $g.FillPath($merc, (RoundRect 176 96 14 96 7))
    $g.FillEllipse($merc, 165, 170, 36, 36)
    $tick = New-Object System.Drawing.Pen (Color '#F5F4EE'), 6
    foreach ($y in 66, 92, 118) { $g.DrawLine($tick, 206, $y, 222, $y) }

    $g.Dispose()
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    , $ms.ToArray()
}

# Archivo .ico con las imágenes en PNG (válido desde Windows Vista).
$sizes = 16, 24, 32, 48, 64, 128, 256
$images = foreach ($s in $sizes) { , (Render $s) }
$fs = [System.IO.File]::Create($out)
$w = New-Object System.IO.BinaryWriter $fs
$w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $s = $sizes[$i] % 256  # 0 significa 256
    $w.Write([byte]$s); $w.Write([byte]$s); $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([uint16]1); $w.Write([uint16]32)
    $w.Write([uint32]$images[$i].Length); $w.Write([uint32]$offset)
    $offset += $images[$i].Length
}
foreach ($img in $images) { $w.Write($img) }
$w.Close()

# Vista previa grande para revisar el diseño.
[System.IO.File]::WriteAllBytes((Join-Path $root 'build\icon_preview.png'), (Render 256))
"Icono generado: $out"
