# İkonu üretir ve EnderChest.exe başlatıcısını .NET Framework derleyicisiyle derler.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
& (Join-Path $PSScriptRoot 'Make-Icon.ps1') -Out (Join-Path $root 'EnderChest.ico')
$csc=@(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
) | Where-Object {Test-Path $_} | Select-Object -First 1
if(!$csc){throw '.NET Framework 4 derleyicisi (csc.exe) bulunamadı.'}
$out=Join-Path $root 'EnderChest.exe'
& $csc /nologo /target:winexe /platform:anycpu /optimize+ /codepage:65001 ('/win32icon:'+(Join-Path $root 'EnderChest.ico')) ('/out:'+$out) (Join-Path $root 'Launcher.cs')
if($LASTEXITCODE -ne 0){throw "Derleme başarısız ($LASTEXITCODE)."}
"Başlatıcı derlendi: $out"
