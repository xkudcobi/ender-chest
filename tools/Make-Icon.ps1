# EnderChest.ico üretir: 16x16 piksel sanattan 16-256 px boyutları.
# Küçük boyutlar BMP, büyükler PNG olarak gömülür (Windows'un beklediği biçim).
param([string]$Out=(Join-Path (Split-Path $PSScriptRoot -Parent) 'EnderChest.ico'))
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$art=@(
    '................',
    '..............v.',
    '.v..............',
    '..############..',
    '.#LLLLLLLLLLLL#.',
    '.#LTTTTTTTTTTL#.',
    '.#TTTTTTTTTTTT#.',
    '.######GG######.',
    '.#BBBBBGGBBBBB#.',
    '.#BddddkkddddB#.',
    '.#BddddddddddB#.',
    '.#BddddddddddB#.',
    '.#BddddddddddB#.',
    '.#BBBBBBBBBBBB#.',
    '.##############.',
    '................'
)
$palette=@{
    '#'='#0d0b14';'L'='#6fe3d6';'T'='#2fa39a';'G'='#f5c542';'k'='#b8862b'
    'B'='#1d4744';'d'='#143533';'v'='#c77dff'
}
function New-Frame($size){
    $scale=$size/16
    $bmp=New-Object Drawing.Bitmap($size,$size,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g=[Drawing.Graphics]::FromImage($bmp)
    $g.Clear([Drawing.Color]::Transparent)
    for($y=0;$y -lt 16;$y++){
        for($x=0;$x -lt 16;$x++){
            $c=[string]$art[$y][$x]
            if($c -eq '.'){continue}
            $brush=New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml($palette[$c]))
            $g.FillRectangle($brush,[int]($x*$scale),[int]($y*$scale),[int][Math]::Ceiling($scale),[int][Math]::Ceiling($scale))
            $brush.Dispose()
        }
    }
    $g.Dispose()
    return $bmp
}
function Get-BmpBytes($bmp){
    # ICO içi DIB: BITMAPINFOHEADER + alttan üste BGRA + AND maskesi (alfa kullanıldığı için sıfır).
    $w=$bmp.Width;$h=$bmp.Height
    $ms=New-Object IO.MemoryStream
    $bw=New-Object IO.BinaryWriter($ms)
    $maskRow=[int]([Math]::Ceiling($w/32))*4
    $bw.Write([int]40);$bw.Write([int]$w);$bw.Write([int]($h*2));$bw.Write([int16]1);$bw.Write([int16]32)
    $bw.Write([int]0);$bw.Write([int]($w*$h*4+$maskRow*$h));$bw.Write([int]0);$bw.Write([int]0);$bw.Write([int]0);$bw.Write([int]0)
    for($y=$h-1;$y -ge 0;$y--){
        for($x=0;$x -lt $w;$x++){
            $p=$bmp.GetPixel($x,$y)
            $bw.Write([byte]$p.B);$bw.Write([byte]$p.G);$bw.Write([byte]$p.R);$bw.Write([byte]$p.A)
        }
    }
    $bw.Write((New-Object byte[] ($maskRow*$h)))
    $bw.Flush()
    return $ms.ToArray()
}
function Get-PngBytes($bmp){
    $ms=New-Object IO.MemoryStream
    $bmp.Save($ms,[Drawing.Imaging.ImageFormat]::Png)
    return $ms.ToArray()
}
$sizes=@(16,32,48,64,128,256)
$images=@()
foreach($s in $sizes){
    $bmp=New-Frame $s
    $images+=,@{size=$s;data=$(if($s -ge 128){Get-PngBytes $bmp}else{Get-BmpBytes $bmp})}
    if($s -eq 256){$bmp.Save([IO.Path]::ChangeExtension($Out,'png'),[Drawing.Imaging.ImageFormat]::Png)}
    $bmp.Dispose()
}
$fs=[IO.File]::Create($Out)
$bw=New-Object IO.BinaryWriter($fs)
$bw.Write([int16]0);$bw.Write([int16]1);$bw.Write([int16]$images.Count)
$offset=6+16*$images.Count
foreach($i in $images){
    $dim=if($i.size -ge 256){0}else{$i.size}
    $bw.Write([byte]$dim);$bw.Write([byte]$dim);$bw.Write([byte]0);$bw.Write([byte]0)
    $bw.Write([int16]1);$bw.Write([int16]32);$bw.Write([int]$i.data.Length);$bw.Write([int]$offset)
    $offset+=$i.data.Length
}
foreach($i in $images){$bw.Write([byte[]]$i.data)}
$bw.Close()
"İkon yazıldı: $Out"
