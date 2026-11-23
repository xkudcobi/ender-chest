# Installs Ender Chest for the current user (no admin rights needed):
#  - copies the app to %LOCALAPPDATA%\Programs\Ender Chest
#  - adds Start menu and desktop shortcuts
#  - gives the desktop chest folder its icon
#  - starts the app; on first start it asks for the language
param([switch]$NoDesktopShortcut,[switch]$NoLaunch)
$ErrorActionPreference='Stop'
$tr=[Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'tr'
function Say($en,$trText){if($tr){$trText}else{$en}}
$src=Split-Path $PSScriptRoot -Parent
if(!(Test-Path (Join-Path $src 'EnderChest.exe')) -or !(Test-Path (Join-Path $src 'EnderChest.ico'))){& (Join-Path $PSScriptRoot 'Build.ps1')}
$running=@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object {$_.CommandLine -like '*EnderChest.ps1*'})
if($running.Count){throw (Say 'Ender Chest is running. Right-click its tray icon, choose Exit, then run the installer again.' 'Ender Chest şu an açık. Tepsi simgesine sağ tıklayıp Çıkış de, sonra kurulumu tekrar çalıştır.')}
$target=Join-Path $env:LOCALAPPDATA 'Programs\Ender Chest'
[void][IO.Directory]::CreateDirectory((Join-Path $target 'fonts'))
foreach($f in 'EnderChest.exe','EnderChest.ps1','DesktopMonitor.ps1','ChestIdentity.cs','PixelUI.cs','Lang.ps1','EnderChest.ico','README.md','LICENSE'){
    $from=Join-Path $src $f
    if(Test-Path -LiteralPath $from){Copy-Item -LiteralPath $from -Destination (Join-Path $target $f) -Force}
}
foreach($f in Get-ChildItem -LiteralPath (Join-Path $src 'fonts') -File){Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $target "fonts\$($f.Name)") -Force}
$exe=Join-Path $target 'EnderChest.exe'
$ico=Join-Path $target 'EnderChest.ico'
$shell=New-Object -ComObject WScript.Shell
function New-Shortcut($path){
    $s=$shell.CreateShortcut($path)
    $s.TargetPath=$exe
    $s.WorkingDirectory=$target
    $s.IconLocation=$ico+',0'
    $s.Description='Gather desktop projects in one chest without breaking their paths'
    $s.Save()
}
$desktop=[Environment]::GetFolderPath('DesktopDirectory')
New-Shortcut (Join-Path ([Environment]::GetFolderPath('Programs')) 'Ender Chest.lnk')
$deskName=Say 'Ender Chest Panel.lnk' 'Ender Chest Paneli.lnk'
if(!$NoDesktopShortcut){New-Shortcut (Join-Path $desktop $deskName)}
# If "start with Windows" is on, point it at the new location.
$run='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
if((Get-ItemProperty -Path $run -ErrorAction SilentlyContinue).'Ender Chest'){
    Set-ItemProperty -Path $run -Name 'Ender Chest' -Value ('"'+$exe+'" --tray')
}
# Chest folder icon (an existing desktop.ini is left alone).
$chest=Join-Path $desktop 'Ender Chest'
[void][IO.Directory]::CreateDirectory($chest)
$ini=Join-Path $chest 'desktop.ini'
if(!(Test-Path -LiteralPath $ini)){
    [IO.File]::WriteAllText($ini,"[.ShellClassInfo]`r`nIconResource=$ico,0`r`n",[Text.Encoding]::Unicode)
    [IO.File]::SetAttributes($ini,'Hidden, System')
    [IO.File]::SetAttributes($chest,([IO.File]::GetAttributes($chest) -bor [IO.FileAttributes]::ReadOnly))
}
try{& (Join-Path $env:WINDIR 'System32\ie4uinit.exe') -show}catch{}
(Say 'Installed: ' 'Kuruldu: ')+$target
if(!$NoLaunch){Start-Process -FilePath $exe;Say 'Ender Chest is starting...' 'Ender Chest açılıyor...'}
