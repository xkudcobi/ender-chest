# Removes the Ender Chest app. Does NOT touch the chest folder, your projects or their desktop links.
$ErrorActionPreference='Stop'
$running=@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object {$_.CommandLine -like '*EnderChest.ps1*'})
if($running.Count){throw 'Ender Chest is running. Right-click its tray icon and choose Exit first. / Ender Chest açık; önce tepsiden Çıkış de.'}
$target=Join-Path $env:LOCALAPPDATA 'Programs\Ender Chest'
$desktop=[Environment]::GetFolderPath('DesktopDirectory')
foreach($lnk in @((Join-Path ([Environment]::GetFolderPath('Programs')) 'Ender Chest.lnk'),(Join-Path $desktop 'Ender Chest Paneli.lnk'),(Join-Path $desktop 'Ender Chest Panel.lnk'))){
    if(Test-Path -LiteralPath $lnk){Remove-Item -LiteralPath $lnk -Force}
}
Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'Ender Chest' -ErrorAction SilentlyContinue
foreach($f in 'EnderChest.exe','EnderChest.ps1','DesktopMonitor.ps1','ChestIdentity.cs','PixelUI.cs','Lang.ps1','EnderChest.ico','README.md','LICENSE'){
    $p=Join-Path $target $f
    if([IO.File]::Exists($p)){[IO.File]::Delete($p)}
}
$fonts=Join-Path $target 'fonts'
if([IO.Directory]::Exists($fonts)){foreach($f in [IO.Directory]::GetFiles($fonts)){[IO.File]::Delete($f)};[IO.Directory]::Delete($fonts,$false)}
if([IO.Directory]::Exists($target) -and ![IO.Directory]::EnumerateFileSystemEntries($target).GetEnumerator().MoveNext()){[IO.Directory]::Delete($target,$false)}
"Removed. Your projects and desktop links are untouched: $(Join-Path $desktop 'Ender Chest')"
