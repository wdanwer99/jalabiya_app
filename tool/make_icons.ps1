# Renders assets/icon/icon.html into the Android launcher icons.
# Needs Google Chrome (or Edge) installed. Run from the project root:
#   powershell -ExecutionPolicy Bypass -File tool/make_icons.ps1
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root "assets/icon/icon.html"
$res = Join-Path $root "android/app/src/main/res"
$tmp = Join-Path ([IO.Path]::GetTempPath()) "jalabiya_icons"
New-Item -ItemType Directory -Force $tmp | Out-Null

$browser = @(
  "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $browser) { throw "Chrome or Edge is needed to render the icon." }

function Render($variant) {
  $out = Join-Path $tmp "$variant.png"
  if (Test-Path $out) { Remove-Item $out }
  # Start-Process does not quote arguments, so no spaces may reach the browser
  $url = "file:///" + (($src -replace '\\', '/') -replace ' ', '%20') + "?v=$variant"
  $args = @("--headless=new", "--hide-scrollbars", "--default-background-color=00000000",
            "--window-size=1024,1024", "`"--screenshot=$out`"", $url)
  Start-Process -FilePath $browser -ArgumentList $args -Wait -WindowStyle Hidden
  if (-not (Test-Path $out)) { throw "Rendering '$variant' failed." }
  return $out
}

function Resize($from, $to, $px) {
  $img = [Drawing.Image]::FromFile($from)
  $bmp = New-Object Drawing.Bitmap $px, $px, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::HighQuality
  $g.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
  $g.Clear([Drawing.Color]::Transparent)
  $g.DrawImage($img, 0, 0, $px, $px)
  New-Item -ItemType Directory -Force (Split-Path $to) | Out-Null
  $bmp.Save($to, [Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose(); $img.Dispose()
}

$full = Render "full"; $store = Render "store"; $fg = Render "fg"; $mono = Render "mono"

# legacy icon 48dp; adaptive layers 108dp. The launcher icon has a transparent
# background (ic_launcher.xml uses @android:color/transparent), so there is no
# background layer to render.
$densities = @{ "mdpi" = 1.0; "hdpi" = 1.5; "xhdpi" = 2.0; "xxhdpi" = 3.0; "xxxhdpi" = 4.0 }
foreach ($d in $densities.Keys) {
  $k = $densities[$d]
  $dir = Join-Path $res "mipmap-$d"
  Resize $full (Join-Path $dir "ic_launcher.png") ([int](48 * $k))
  Resize $fg   (Join-Path $dir "ic_launcher_foreground.png") ([int](108 * $k))
  Resize $mono (Join-Path $dir "ic_launcher_monochrome.png") ([int](108 * $k))
}
# the 512 px icon the Play Store asks for: opaque, with the navy background
Resize $store (Join-Path $root "assets/icon/play_store_512.png") 512

Write-Host "Icons written to $res"
