Add-Type -AssemblyName System.Drawing

$root = 'D:/Work/WorkBuddy_File/account'
$labels = Get-Content -Raw -Encoding UTF8 "$root/tools/screenshot/mock-labels.json" | ConvertFrom-Json

$W = 880
$H = 806
$bmp = New-Object System.Drawing.Bitmap($W, $H)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
$g.Clear([System.Drawing.ColorTranslator]::FromHtml('#EDEAE4'))

function C([string]$hex) { [System.Drawing.ColorTranslator]::FromHtml($hex) }
function A([int]$alpha) { [System.Drawing.Color]::FromArgb($alpha, 29, 28, 26) }

function RoundPath([double]$x, [double]$y, [double]$pw, [double]$ph, [double]$r) {
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = [double]($r * 2)
  $p.AddArc([float]$x, [float]$y, [float]$d, [float]$d, 180, 90)
  $p.AddArc([float]($x + $pw - $d), [float]$y, [float]$d, [float]$d, 270, 90)
  $p.AddArc([float]($x + $pw - $d), [float]($y + $ph - $d), [float]$d, [float]$d, 0, 90)
  $p.AddArc([float]$x, [float]($y + $ph - $d), [float]$d, [float]$d, 90, 90)
  $p.CloseFigure()
  return $p
}

$fontTitle = New-Object System.Drawing.Font('Microsoft YaHei', 12, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$fontSec = New-Object System.Drawing.Font('Microsoft YaHei', 14, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$fontRow = New-Object System.Drawing.Font('Microsoft YaHei', 14, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$fontSmall = New-Object System.Drawing.Font('Microsoft YaHei', 11, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)

$ink = New-Object System.Drawing.SolidBrush((C '#1D1C1A'))
$inkRow = New-Object System.Drawing.SolidBrush((A 158))
$inkSmall = New-Object System.Drawing.SolidBrush((C '#8A867D'))
$inkPlus = New-Object System.Drawing.SolidBrush((A 87))
$white = New-Object System.Drawing.SolidBrush((C '#FFFFFF'))

$g.DrawString($labels.secA, $fontSec, $ink, 20, 12)
$g.DrawString($labels.secB, $fontSec, $ink, 20, 520)

function Draw-Stack([double]$ox, [double]$oy, [string]$mode) {
  $vw = 390.0
  $vh = 150.0
  $frame = RoundPath $ox $oy $vw $vh 14
  $bgBrush = New-Object System.Drawing.SolidBrush((C '#F7F5F1'))
  $g.FillPath($bgBrush, $frame)
  $g.SetClip($frame)

  $n = 7; $t = 10
  $shrink = 0
  $fade = $false
  if ($mode -eq 's1') { $n = 4 }
  if ($mode -eq 's2') { $n = 4; $t = 12; $shrink = 6 }
  if ($mode -eq 's3') { $n = 3; $fade = $true }

  for ($d = $n - 1; $d -ge 0; $d--) {
    $bottom = 8 + $t * ($n - 1 - $d)
    $lr = 16 + $shrink * $d
    $ch = 260
    $cy = $oy + $vh - $bottom - $ch
    $cw = $vw - 2 * $lr
    $path = RoundPath ($ox + $lr) $cy $cw $ch 24
    $alpha = 255
    if ($fade) { $alpha = [int][Math]::Max(90, 255 - $d * 46) }
    $fill = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($alpha, 255, 255, 255))
    $g.FillPath($fill, $path)
    $pen = New-Object System.Drawing.Pen(([System.Drawing.Color]::FromArgb([int]($alpha * 0.11), 29, 28, 26)), 1)
    $g.DrawPath($pen, $path)

    # 上层卡压在下一层上，正下方那 9pt 是它的投影
    $bandY = $cy + $ch
    $bandH = 10
    if ($bandY + $bandH -lt $oy + $vh - 2) {
      $brect = New-Object System.Drawing.Rectangle([int]($ox + $lr + 2), [int]$bandY, [int]($cw - 4), [int]$bandH)
      $bg2 = New-Object System.Drawing.Drawing2D.LinearGradientBrush($brect, [System.Drawing.Color]::FromArgb(34, 29, 28, 26), [System.Drawing.Color]::FromArgb(0, 29, 28, 26), [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
      $g.FillRectangle($bg2, $brect)
    }
  }

  if ($mode -eq 's3') {
    $rect = New-Object System.Drawing.Rectangle([int]$ox, [int]($oy + $vh - 26), [int]$vw, 26)
    $gb = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, [System.Drawing.Color]::FromArgb(0, 29, 28, 26), [System.Drawing.Color]::FromArgb(20, 29, 28, 26), [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
    $g.FillRectangle($gb, $rect)
  }

  $g.ResetClip()
  $pen2 = New-Object System.Drawing.Pen((C '#DED9D0'), 1)
  $g.DrawPath($pen2, $frame)
}

function Draw-Row([double]$ox, [double]$oy, [string]$mode) {
  $vw = 390.0
  $vh = 76.0
  $frame = RoundPath $ox $oy $vw $vh 14
  $wbrush = New-Object System.Drawing.SolidBrush((C '#FFFFFF'))
  $g.FillPath($wbrush, $frame)
  $g.DrawPath((New-Object System.Drawing.Pen((C '#E3DED5'), 1)), $frame)

  $sx = $ox + 18
  $sy = $oy + ($vh - 42) / 2

  if ($mode -eq 'b3') {
    $g.DrawString(($labels.plusText + ' ' + $labels.rowLabel), $fontRow, $inkRow, [float]($sx), [float]($sy + 10))
  } else {
    $slotPath = RoundPath $sx $sy 42 42 13
    if ($mode -eq 'b1') {
      $fill = New-Object System.Drawing.SolidBrush((C '#FCFBF8'))
      $g.FillPath($fill, $slotPath)
      $pen = New-Object System.Drawing.Pen((A 46), 1)
      $pen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
      $g.DrawPath($pen, $slotPath)
    } elseif ($mode -eq 'b2') {
      $fill = New-Object System.Drawing.SolidBrush((C '#F6F3EC'))
      $g.FillPath($fill, $slotPath)
    } else {
      $fill = New-Object System.Drawing.SolidBrush((C '#FFFFFF'))
      $g.FillPath($fill, $slotPath)
      $pen = New-Object System.Drawing.Pen((A 31), 1)
      $g.DrawPath($pen, $slotPath)
    }
    $pc = $inkPlus
    if ($mode -eq 'b4') { $pc = New-Object System.Drawing.SolidBrush((A 128)) }
    $penP = New-Object System.Drawing.Pen($pc, 2)
    $cx = $sx + 21
    $cyy = $sy + 21
    $g.DrawLine($penP, [float]($cx - 7), [float]$cyy, [float]($cx + 7), [float]$cyy)
    $g.DrawLine($penP, [float]$cx, [float]($cyy - 7), [float]$cx, [float]($cyy + 7))
    $g.DrawString($labels.rowLabel, $fontRow, $inkRow, [float]($sx + 54), [float]($sy + 10))
  }

  $sz = $g.MeasureString($labels.rowRight, $fontSmall)
  $g.DrawString($labels.rowRight, $fontSmall, $inkSmall, [float]($ox + $vw - 18 - $sz.Width), [float]($sy + 12))
}

$cols = @(16, 458)
$i = 0
foreach ($s in $labels.stacks) {
  $cx = $cols[$i % 2]
  $cy = 44 + [Math]::Floor($i / 2) * 232
  $g.DrawString($s.title, $fontTitle, $ink, [float]$cx, [float]$cy)
  Draw-Stack $cx ($cy + 22) $s.mode
  $i++
}

$i = 0
foreach ($s in $labels.slots) {
  $cx = $cols[$i % 2]
  $cy = 552 + [Math]::Floor($i / 2) * 128
  $g.DrawString($s.title, $fontTitle, $ink, [float]$cx, [float]$cy)
  Draw-Row $cx ($cy + 22) $s.mode
  $i++
}

$g.Dispose()
$bmp.Save("$root/design/current/_slots.png", [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output "saved _slots.png"
