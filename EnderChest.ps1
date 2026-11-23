param([switch]$Test,[switch]$MonitorTest,[switch]$IntegrationTest,[switch]$SafetyTest,[switch]$FeatureTest,[switch]$GroupTest,[switch]$LangTest,[switch]$Tray,[switch]$Demo,[string]$DemoLang='en',[string]$Snapshot,[string]$DemoDialog)
$ErrorActionPreference='Stop'
$testing=$Test -or $MonitorTest -or $IntegrationTest -or $SafetyTest -or $FeatureTest -or $GroupTest -or $LangTest
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
# Piksel arayüz kiti, fontlar ve diller
Add-Type -Path (Join-Path $PSScriptRoot 'PixelUI.cs') -ReferencedAssemblies System.Windows.Forms,System.Drawing
[Px]::LoadFonts((Join-Path $PSScriptRoot 'fonts'))
. (Join-Path $PSScriptRoot 'Lang.ps1')
$shell=New-Object -ComObject WScript.Shell
function Assert-Local($path){
    $root=[IO.Path]::GetPathRoot($path)
    $drive=[IO.DriveInfo]::new($root)
    if($drive.DriveType -ne 'Fixed' -or $drive.DriveFormat -ne 'NTFS'){throw (T 'err.notNtfs')}
    foreach($cloud in @($env:OneDrive,$env:OneDriveConsumer,$env:OneDriveCommercial)){
        if($cloud -and ($path+'\').StartsWith($cloud.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw (T 'err.oneDrive')}
    }
    for($node=[IO.DirectoryInfo]::new($path);$node;$node=$node.Parent){
        if($node.Attributes -band [IO.FileAttributes]::ReparsePoint){throw (T 'err.underLink')}
    }
}
function New-Bridge($path,$target){
    New-Item -ItemType Junction -Path $path -Target $target -ErrorAction Stop | Out-Null
}
function Is-Bridge($path,$target){
    $j=Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    return ($j -and $j.LinkType -eq 'Junction' -and (@($j.Target) -contains $target))
}
# --- Kalıcı durum: sandığın içinde gizli+sistem '.enderchest' klasörü ---
# Gizli+sistem olduğu için proje listelerine ve izleyiciye hiç girmez.
function Get-StateDir {
    $s=Join-Path $dir '.enderchest'
    if(![IO.Directory]::Exists($s)){
        [void][IO.Directory]::CreateDirectory($s)
        [IO.File]::SetAttributes($s,([IO.File]::GetAttributes($s) -bor [IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System))
    }
    return $s
}
function Write-StateFile($name,$value){
    # Önce geçici dosyaya yaz, sonra yer değiştir: yarım yazılmış durum dosyası kalmaz.
    $path=Join-Path (Get-StateDir) $name
    $tmp=$path+'.tmp'
    [IO.File]::WriteAllText($tmp,(ConvertTo-Json -InputObject $value -Depth 5 -Compress),(New-Object Text.UTF8Encoding $false))
    # Not: PowerShell $null'ı metin parametresine "" olarak geçirir; yedek dosya istemediğimizi [NullString] ile söylüyoruz.
    if([IO.File]::Exists($path)){[IO.File]::Replace($tmp,$path,[NullString]::Value)}else{[IO.File]::Move($tmp,$path)}
}
function Read-StateFile($name){
    $path=Join-Path (Get-StateDir) $name
    if(![IO.File]::Exists($path)){return $null}
    try{return ([IO.File]::ReadAllText($path) | ConvertFrom-Json)}catch{return $null}
}
# Proje kaydı ve grup işlevleri DesktopMonitor.ps1 içindedir (klasör kimliğini kullanırlar).
# --- İşlem günlüğü: taşıma/geri alma yarıda kalırsa bir sonraki açılışta tamamlanır ---
function Start-Journal($op,$old,$dest){
    $file=Join-Path (Get-StateDir) ('pending-'+[guid]::NewGuid()+'.json')
    $entry=@{op=$op;old=$old;dest=$dest;time=(Get-Date).ToString('o')}
    [IO.File]::WriteAllText($file,(ConvertTo-Json -InputObject $entry -Compress),(New-Object Text.UTF8Encoding $false))
    return $file
}
function Stop-Journal($file){if($file -and [IO.File]::Exists($file)){[IO.File]::Delete($file)}}
function Test-RealFolder($path){
    return ([IO.Directory]::Exists($path) -and !([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint))
}
function Resume-Journal {
    $messages=@()
    foreach($file in [IO.Directory]::GetFiles((Get-StateDir),'pending-*.json')){
        try{$j=[IO.File]::ReadAllText($file) | ConvertFrom-Json}catch{$j=$null}
        # Okunamayan günlük, taşımaya başlanmadan önce yazılırken kesilmiştir: dosyalara dokunulmamıştır.
        if(!$j -or !$j.old -or !$j.dest){Stop-Journal $file;continue}
        $name=[IO.Path]::GetFileName($j.dest)
        $oldItem=Get-Item -LiteralPath $j.old -Force -ErrorAction SilentlyContinue
        try{
            if($name -like 'EnderChest-Test-*'){
                # Açılış denemesi yarıda kalmış: boş deneme klasörlerini temizle.
                if(Is-Bridge $j.old $j.dest){[IO.Directory]::Delete($j.old,$false)}
                foreach($p in @($j.dest,$j.old)){if((Test-RealFolder $p) -and ![IO.Directory]::EnumerateFileSystemEntries($p).GetEnumerator().MoveNext()){[IO.Directory]::Delete($p,$false)}}
            }elseif(!$oldItem -and (Test-RealFolder $j.dest)){
                # Proje sandıkta, eski yol yok: işlem tam ortada kesilmiş.
                if($j.op -eq 'restore'){
                    try{[IO.Directory]::Move($j.dest,$j.old);$messages+=(T 'j.restoreDone' $name)}
                    catch{
                        New-Bridge $j.old $j.dest
                        [IO.File]::SetAttributes($j.old,([IO.File]::GetAttributes($j.old) -bor 6))
                        $messages+=(T 'j.restoreRelinked' $name)
                    }
                }else{
                    New-Bridge $j.old $j.dest
                    if(!(Is-Bridge $j.old $j.dest)){throw (T 'err.verifyOld')}
                    [IO.File]::SetAttributes($j.old,([IO.File]::GetAttributes($j.old) -bor 6))
                    Set-ProjectRecord $j.dest $j.old
                    $messages+=(T 'j.moveDone' $name)
                }
            }elseif($oldItem -and $oldItem.LinkType -eq 'Junction' -and !(Is-Bridge $j.old $j.dest) -and (Test-RealFolder $j.dest) -and ![IO.Directory]::Exists([string](@($oldItem.Target)[0]))){
                # Gruba taşıma yarıda kalmış: proje yeni yerinde, bağlantı eski hedefi gösteriyor.
                [IO.Directory]::Delete($j.old,$false)
                New-Bridge $j.old $j.dest
                [IO.File]::SetAttributes($j.old,([IO.File]::GetAttributes($j.old) -bor 6))
                Set-ProjectRecord $j.dest $j.old
                $messages+=(T 'j.regroupDone' $name)
            }elseif($oldItem -and !(Is-Bridge $j.old $j.dest) -and (Test-RealFolder $j.dest)){
                # İki yerde de gerçek klasör var: hiçbirine dokunma, kullanıcıya bildir.
                $messages+=(T 'j.both' $j.old $j.dest)
            }
            # Diğer durumlar zaten tutarlı: işlem hiç başlamamış ya da tamamlanmış.
            Stop-Journal $file
        }catch{
            $messages+=(T 'j.failed' $name $_.Exception.Message $j.dest)
        }
    }
    return $messages
}
# --- Kullanımdaki klasör kontrolü ---
function Find-FolderUsers($path){
    $prefix=$path.TrimEnd('\')+'\'
    $hits=@()
    try{$procs=@(Get-CimInstance Win32_Process -ErrorAction Stop)}catch{return @()}
    foreach($p in $procs){
        if($p.ProcessId -eq $PID){continue}
        $exe=[string]$p.ExecutablePath
        $cmd=[string]$p.CommandLine
        if($exe.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or $cmd.IndexOf($prefix,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or $cmd.TrimEnd('"',' ').EndsWith($path,[StringComparison]::OrdinalIgnoreCase)){
            $hits+=('{0} (PID {1})' -f $p.Name,$p.ProcessId)
        }
    }
    return @($hits | Select-Object -Unique)
}
function Format-MoveError($err,$path){
    $ex=$err.Exception
    while($ex.InnerException){$ex=$ex.InnerException}
    if($ex -is [IO.IOException] -or $ex -is [UnauthorizedAccessException]){
        $m=(T 'err.inUse' $path)
        $users=@(Find-FolderUsers $path)
        if($users.Count){$m+="`n`n"+(T 'err.inUseWho')+"`n"+($users -join "`n")}
        return $m+"`n`n("+$ex.Message.Trim()+")"
    }
    return $ex.Message
}
function Move-Project($folder,$group=''){
    $old=$folder.FullName
    $dest=Join-Path (Get-GroupPath $group) $folder.Name
    Assert-Local $old
    Assert-Local $dir
    if($dir -eq $old -or $dir.StartsWith($old+'\',[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetPathRoot($dest) -ne [IO.Path]::GetPathRoot($old)){throw (T 'err.sameDisk')}
    # Proje adları sandığın tamamında (tüm gruplarda) benzersiz olmalı.
    $clash=@(Get-ChestProjects | Where-Object {$_.Name -eq $folder.Name} | ForEach-Object {$_.FullName})
    if(Get-Item -LiteralPath (Join-Path $dir $folder.Name) -Force -ErrorAction SilentlyContinue){$clash+=(Join-Path $dir $folder.Name)}
    if(Get-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue){$clash+=$dest}
    if($clash.Count){throw (T 'err.nameClash' (@($clash | Select-Object -Unique) -join "`n"))}
    $attrs=[IO.File]::GetAttributes($old)
    $journal=Start-Journal 'move' $old $dest
    try{[IO.Directory]::Move($old,$dest)}catch{
        Stop-Journal $journal
        throw (Format-MoveError $_ $old)
    }
    try{
        New-Bridge $old $dest
        if(!(Is-Bridge $old $dest)){throw (T 'err.verifyOld')}
        [IO.File]::SetAttributes($old,([IO.File]::GetAttributes($old) -bor 6))
        if($attrs -band 2){[IO.File]::SetAttributes($dest,($attrs -band (-bnot 2)))}
    }catch{
        $reason=$_.Exception.Message + " (" + $_.InvocationInfo.Line.Trim() + ")"
        if(Is-Bridge $old $dest){[IO.Directory]::Delete($old,$false)}
        if(!(Test-Path -LiteralPath $old)){[IO.Directory]::Move($dest,$old)}
        # Geri alma başarılıysa günlüğü kapat; başarısızsa günlük kalır ve açılışta kurtarılır.
        Stop-Journal $journal
        throw (T 'err.moveFailed' $reason)
    }
    Stop-Journal $journal
    Set-ProjectRecord $dest $old
    $legacy=Join-Path $dir ($folder.Name+'.lnk')
    if([IO.File]::Exists($legacy) -and $shell.CreateShortcut($legacy).TargetPath -eq $old){[IO.File]::Delete($legacy)}
}
function Restore-Project($folder){
    $old=$folder.FullName
    # Proje sandığın kökünde veya bir grubun içinde olabilir: bağlantının gösterdiği yer esas alınır.
    $dest=Get-ChestTarget $old
    if(!$dest){throw (T 'err.notMoved')}
    Assert-Local $dest
    $journal=Start-Journal 'restore' $old $dest
    [IO.Directory]::Delete($old,$false)
    try{[IO.Directory]::Move($dest,$old)}catch{
        $err=$_
        if(!(Test-Path -LiteralPath $old)){
            New-Bridge $old $dest
            [IO.File]::SetAttributes($old,([IO.File]::GetAttributes($old) -bor 6))
        }
        Stop-Journal $journal
        throw (Format-MoveError $err $dest)
    }
    Stop-Journal $journal
    Remove-ProjectRecord $old
}
function Move-ProjectToGroup($linkPath,$group){
    # Sandıktaki projeyi başka bir gruba taşır ve eski yolu yeni konuma yönlendirir.
    $target=Get-ChestTarget $linkPath
    if(!$target){throw (T 'err.moveFirst')}
    $name=[IO.Path]::GetFileName($target)
    $new=Join-Path (Get-GroupPath $group) $name
    if($new -eq $target){return}
    if(Get-Item -LiteralPath $new -Force -ErrorAction SilentlyContinue){throw (T 'err.groupClash' $new)}
    $journal=Start-Journal 'move' $linkPath $new
    try{[IO.Directory]::Move($target,$new)}catch{
        Stop-Journal $journal
        throw (Format-MoveError $_ $target)
    }
    [IO.Directory]::Delete($linkPath,$false)
    New-Bridge $linkPath $new
    if(!(Is-Bridge $linkPath $new)){throw (T 'err.retarget')}
    [IO.File]::SetAttributes($linkPath,([IO.File]::GetAttributes($linkPath) -bor 6))
    Stop-Journal $journal
    Set-ProjectRecord $new $linkPath
}
function Pick($title,$initial){
    $d=New-Object Windows.Forms.FolderBrowserDialog
    $d.Description=$title
    $d.SelectedPath=$initial
    if($d.ShowDialog() -eq 'OK'){return $d.SelectedPath}
}
# --- Temalı mesajlar ---
$form=$null
function Note($msg){
    if($testing){$script:lastNote=$msg;return}
    [void][PixelDialog]::Show($form,'Ender Chest',[string]$msg,[string[]]@((T 'dlg.ok')),0)
}
function Ask($msg,$title){
    if($testing){return $true}
    return ([PixelDialog]::Show($form,[string]$title,[string]$msg,[string[]]@((T 'dlg.no'),(T 'dlg.yes')),1) -eq 1)
}
[Windows.Forms.Application]::EnableVisualStyles()
$desktop=[Environment]::GetFolderPath('DesktopDirectory')
if($testing -or $Demo){
    $parent=[IO.Directory]::CreateDirectory((Join-Path $env:TEMP ([guid]::NewGuid()))).FullName
    $desktop=$parent
}else{$parent=$desktop}
if(!$parent){return}
$dir=if((Split-Path $parent -Leaf) -eq 'Ender Chest'){$parent}else{Join-Path $parent 'Ender Chest'}
[void][IO.Directory]::CreateDirectory($dir)
$iconPath=Join-Path $PSScriptRoot 'EnderChest.ico'
$appIcon=$null
if([IO.File]::Exists($iconPath)){try{$appIcon=New-Object Drawing.Icon($iconPath)}catch{$appIcon=$null}}
[PixelDialog]::AppIcon=$appIcon

# --- Ayarlar ---
function Get-Settings {
    $s=Read-StateFile 'settings.json'
    $excluded=@()
    if($s -and $s.excluded){$excluded=@($s.excluded | ForEach-Object {[string]$_})}
    $lastGroup=if($s -and $s.lastGroup){[string]$s.lastGroup}else{''}
    $language=if($s -and $s.language){[string]$s.language}else{''}
    return @{excluded=$excluded;lastGroup=$lastGroup;language=$language}
}
function Save-Settings($s){Write-StateFile 'settings.json' $s}

# --- Tek kopya ve dil (arayüz kurulmadan önce) ---
if($testing){
    Set-Language 'tr'
}elseif($Demo){
    Set-Language $DemoLang
}else{
    $mutex=[Threading.Mutex]::new($false,'Local\EnderChestDesktop3')
    $showEvent=New-Object Threading.EventWaitHandle($false,[Threading.EventResetMode]::AutoReset,'Local\EnderChestShow3')
    # Zaten açıksa: açık olan pencereyi öne getir ve sessizce çık.
    if(!$mutex.WaitOne(0)){[void]$showEvent.Set();return}
    $settings=Get-Settings
    if(!$settings.language){
        # İlk açılış: dili sor. Varsayılan, Windows'un dili.
        $codes=@($Languages.Keys)
        $guess=Get-DefaultLanguage
        Set-Language $guess
        $pick=[PixelDialog]::Choose($null,'Language · Dil · Sprache · Idioma',(T 'lang.text'),[string[]]@($Languages.Values),[array]::IndexOf($codes,$guess))
        $settings.language=if($pick -ge 0){$codes[$pick]}else{$guess}
        try{Save-Settings $settings}catch{}
    }
    Set-Language $settings.language
}

# --- Ana pencere ---
$version='3.4'
$form=New-Object PixelForm
$form.Text='Ender Chest'
$form.Font=[Px]::Body(16)
$form.ClientSize='760,724'
$form.StartPosition='CenterScreen'
$form.FormBorderStyle='FixedSingle'
$form.MaximizeBox=$false
if($appIcon){$form.Icon=$appIcon}
$i18n=New-Object Collections.ArrayList
function Widget($type,$key,$x,$y,$w,$h,$font){
    $c=New-Object $type
    if($key){$c.Text=T $key;[void]$i18n.Add(@{c=$c;k=$key})}
    if($font){$c.Font=$font}
    $c.SetBounds($x,$y,$w,$h)
    $form.Controls.Add($c)
    return $c
}
$bold=[Px]::Body(16,$true)
$title=Widget PixelLabel '' 104 26 280 30 ([Px]::Display(24))
$title.Text='ENDER CHEST'
$badge=Widget PixelLabel '' 386 34 120 16 ([Px]::Display(8))
$badge.Text="v$version BETA"
$badge.ForeColor=[Px]::Teal
$subtitle=Widget PixelLabel 'app.subtitle' 104 62 500 36 $null
$subtitle.ForeColor=[Px]::Dim
$langSelect=Widget PixelSelect '' 612 30 124 40 $bold
foreach($n in $Languages.Values){$langSelect.Items.Add($n)}
$langSelect.SelectedIndex=[array]::IndexOf(@($Languages.Keys),$script:Lang)

$source=Widget PixelLabel '' 26 120 400 32 $null
$source.Ellipsis=$true
$source.VAlign='Center'
$source.ForeColor=[Px]::Dim
$pickProjects=Widget PixelButton 'btn.pickProjects' 436 116 160 40 $bold
$browse=Widget PixelButton 'btn.browse' 604 116 132 40 $bold

$listHeader=Widget PixelHeader '' 30 172 700 32 $bold
$list=Widget PixelList '' 30 204 700 218 $null
$list.MultiSelect=$true
$list.AllowDrop=$true
[void]$list.Columns.Add((T 'col.folder'),300)
[void]$list.Columns.Add((T 'col.kind'),180)
[void]$list.Columns.Add((T 'col.status'),200)
$listHeader.List=$list
$listMenu=New-Object Windows.Forms.ContextMenuStrip
$listMenu.Renderer=New-Object PixelMenuRenderer
$listMenu.Font=$form.Font
$excludeItem=$listMenu.Items.Add((T 'menu.exclude'))
$list.ContextMenuStrip=$listMenu

$meter=Widget PixelMeter '' 24 438 712 28 $null
$hide=Widget PixelLabel 'status.ready' 24 472 712 26 $null
$hide.ForeColor=[Px]::TealHi
$hide.Ellipsis=$true
$hide.VAlign='Center'

$groupLabel=Widget PixelLabel 'lbl.group' 38 514 72 40 ([Px]::Display(8))
$groupLabel.VAlign='Center'
$groupLabel.ForeColor=[Px]::Dim
$groupBox=Widget PixelSelect '' 112 514 262 40 $bold
$newGroup=Widget PixelButton 'btn.newGroup' 384 514 168 40 $bold
$regroup=Widget PixelButton 'btn.regroup' 560 514 164 40 $bold

$add=Widget PixelButton 'btn.add' 24 578 304 54 ([Px]::Body(20,$true))
$add.Variant=1
$restore=Widget PixelButton 'btn.restore' 338 578 196 54 $bold
$open=Widget PixelButton 'btn.open' 542 578 194 54 $bold
$repair=Widget PixelButton 'btn.repair' 24 642 352 42 $bold
$healthBtn=Widget PixelButton 'btn.health' 386 642 350 42 $bold
$autostart=Widget PixelCheck 'chk.autostart' 24 692 712 26 $null

$form.Add_Paint({param($s,$e)
    $g=$e.Graphics
    [Px]::Banner($g,$form.ClientSize.Width,104)
    [Px]::Chest($g,24,20,4)
    [Px]::Slot($g,(New-Object Drawing.Rectangle 24,166,712,262))
    [Px]::Plate($g,(New-Object Drawing.Rectangle 24,506,712,56))
})
$repair.Add_Click({
    try{
        $p=Pick (T 'pick.repair') $dir
        if($p){Repair-DesktopPath (Get-Item -Force -LiteralPath $p);Load-Folders $desktop}
    }catch{Note $_.Exception.Message}
})

# --- Dil değişimi ---
function Apply-Language {
    foreach($e in $i18n){$e.c.Text=T $e.k}
    $list.Columns[0].Text=T 'col.folder'
    $list.Columns[1].Text=T 'col.kind'
    $list.Columns[2].Text=T 'col.status'
    $listHeader.Invalidate()
    $excludeItem.Text=T 'menu.exclude'
    if($trayMenu){
        $miOpen.Text=T 'tray.open';$miChest.Text=T 'tray.chest';$miHealth.Text=T 'tray.health';$miExit.Text=T 'tray.exit'
        $trayIcon.Text=T 'tray.watching'
    }
    Refresh-Groups
    if($source.Text){Load-Folders $source.Text}
    $hide.Text=if($trayIcon){T 'status.watching'}else{T 'status.ready'}
    $form.Invalidate($true)
}
$langSelect.Add_SelectionChanged({
    try{
        $code=@($Languages.Keys)[$langSelect.SelectedIndex]
        Set-Language $code
        $s=Get-Settings;$s.language=$code;Save-Settings $s
        Apply-Language
    }catch{Note $_.Exception.Message}
})

# --- Proje algılama ---
$projectMarkers=[ordered]@{
    'package.json'='Node';'.git'='Git';'Cargo.toml'='Rust';'go.mod'='Go';'pyproject.toml'='Python';'requirements.txt'='Python'
    'pom.xml'='Java';'build.gradle'='Java';'composer.json'='PHP';'Gemfile'='Ruby';'pubspec.yaml'='Flutter';'index.html'='Web'
}
function Get-ProjectKind($path){
    # Yalnız üst düzeydeki işaret dosyalarına bakar; proje içeriği taranmaz.
    $names=@{}
    try{foreach($e in [IO.Directory]::EnumerateFileSystemEntries($path)){$names[[IO.Path]::GetFileName($e)]=$true}}catch{return ''}
    $kinds=@()
    foreach($k in $projectMarkers.Keys){if($names.ContainsKey($k) -and $kinds -notcontains $projectMarkers[$k]){$kinds+=$projectMarkers[$k]}}
    foreach($n in $names.Keys){if($n -like '*.sln' -or $n -like '*.csproj'){$kinds+='.NET';break}}
    return ($kinds -join ', ')
}
$noKind='—'

# --- Grup seçici ---
function Refresh-Groups {
    $current=if($groupBox.SelectedIndex -gt 0){[string]$groupBox.SelectedItem}else{(Get-Settings).lastGroup}
    $groupBox.Items.Clear()
    $groupBox.Items.Add((T 'group.none'))
    foreach($g in Get-Groups){$groupBox.Items.Add($g.Name)}
    $i=if($current){$groupBox.Items.IndexOf($current)}else{0}
    $groupBox.SelectedIndex=if($i -ge 0){$i}else{0}
}
function Get-SelectedGroup {if($groupBox.SelectedIndex -gt 0){return [string]$groupBox.SelectedItem};return ''}

# --- Liste ---
function Get-LinkedTargets {
    foreach($entry in Get-ChildItem -LiteralPath $dir -Filter '*.lnk' -File){
        try{$shell.CreateShortcut($entry.FullName).TargetPath}catch{continue}
    }
}
function Load-Folders($path){
    $targets=@(Get-LinkedTargets)
    $items=@(Get-ChildItem -LiteralPath $path -Directory -Force | Where-Object {
        $_.FullName -ne $dir -and (!($_.Attributes -band [IO.FileAttributes]::System) -or (Get-ChestTarget $_.FullName)) -and
        (!($_.Attributes -band [IO.FileAttributes]::Hidden) -or (($targets -contains $_.FullName) -or (Get-ChestTarget $_.FullName)))
    })
    $settings=Get-Settings
    $source.Text=$path
    $list.BeginUpdate()
    $list.Items.Clear()
    $inChest=0
    foreach($item in $items){
        $row=$list.Items.Add($item.Name)
        $row.Tag=$item
        $row.UseItemStyleForSubItems=$false
        $target=Get-ChestTarget $item.FullName
        $bridged=[bool]$target
        if($bridged){$inChest++}
        $kind=if($bridged){''}else{Get-ProjectKind $item.FullName}
        $inGroup=if($bridged -and (Split-Path $target -Parent) -ne $dir){' · '+(Split-Path (Split-Path $target -Parent) -Leaf)}else{''}
        $state=if($bridged){(T 'st.inChest')+$inGroup}elseif($settings.excluded -contains $item.FullName){T 'st.excluded'}else{''}
        $kindCell=$row.SubItems.Add($(if($kind){$kind}else{$noKind}))
        $stateCell=$row.SubItems.Add($state)
        $kindCell.ForeColor=if($kind){[Px]::Gold}else{[Px]::Faint}
        if($bridged){$row.ForeColor=[Px]::TealHi;$stateCell.ForeColor=[Px]::Teal}
        elseif($state){$row.ForeColor=[Px]::Faint;$stateCell.ForeColor=[Px]::Faint}
        else{$row.ForeColor=[Px]::Ink;$stateCell.ForeColor=[Px]::Dim}
    }
    $list.EndUpdate()
    $list.FitColumns()
    if($path -eq $desktop){$meter.SetValue($inChest,$items.Count,(T 'meter.caption'),(T 'meter.detail' $inChest $items.Count))}
    $restore.Enabled=$true
}
function Select-Projects {
    $n=0
    foreach($row in $list.Items){
        $pickRow=($row.SubItems[1].Text -ne $noKind) -and !$row.SubItems[2].Text
        $row.Selected=$pickRow
        if($pickRow){$n++}
    }
    $list.Focus() | Out-Null
    if($n){$hide.Text=T 'sel.count' $n}else{Note (T 'sel.none')}
    return $n
}
function Select-DesktopFolders([string[]]$paths){
    $existing=@()
    if($source.Text -eq $desktop){$existing=@($list.SelectedItems | ForEach-Object {$_.Tag.FullName})}
    Load-Folders $desktop
    $accepted=0
    foreach($row in $list.Items){
        $match=$paths -contains $row.Tag.FullName
        $row.Selected=$match -or ($existing -contains $row.Tag.FullName)
        if($match){$accepted++}
    }
    $list.Focus() | Out-Null
    if($accepted -lt $paths.Count){Note (T 'sel.onlyDesktop')}
}
$list.Add_DragEnter({param($sender,$e)
    if($e.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)){$e.Effect=[Windows.Forms.DragDropEffects]::Copy}
})
$list.Add_DragDrop({param($sender,$e)
    try{Select-DesktopFolders ($e.Data.GetData([Windows.Forms.DataFormats]::FileDrop))}catch{Note $_.Exception.Message}
})
$browse.Add_Click({try{$p=Pick (T 'pick.source') $source.Text;if($p){Load-Folders $p}}catch{Note $_.Exception.Message}})
$pickProjects.Add_Click({try{[void](Select-Projects)}catch{Note $_.Exception.Message}})
$excludeItem.Add_Click({
    try{
        if(!$list.SelectedItems.Count){throw (T 'err.selectFirst')}
        $ex=New-Object Collections.ArrayList
        foreach($p in (Get-Settings).excluded){[void]$ex.Add($p)}
        foreach($row in @($list.SelectedItems)){
            $p=$row.Tag.FullName
            if($ex -contains $p){$ex.Remove($p)}else{[void]$ex.Add($p)}
        }
        $s=Get-Settings
        $s.excluded=@($ex)
        Save-Settings $s
        Load-Folders $source.Text
    }catch{Note $_.Exception.Message}
})
$groupBox.Add_SelectionChanged({
    try{$s=Get-Settings;$s.lastGroup=Get-SelectedGroup;Save-Settings $s}catch{}
})
$newGroup.Add_Click({
    try{
        $name=[PixelDialog]::Input($form,(T 'grp.title'),(T 'grp.prompt'),(T 'dlg.ok'),(T 'dlg.cancel'),'')
        if(!$name){return}
        $path=New-Group $name
        Refresh-Groups
        $groupBox.SelectedIndex=[Math]::Max(0,$groupBox.Items.IndexOf((Split-Path $path -Leaf)))
        $s=Get-Settings;$s.lastGroup=Get-SelectedGroup;Save-Settings $s
        $hide.Text=T 'grp.ready' (Split-Path $path -Leaf)
    }catch{Note $_.Exception.Message}
})
function Move-SelectionToGroup {
    try{
        $rows=@($list.SelectedItems | Where-Object {Get-ChestTarget $_.Tag.FullName})
        if(!$rows.Count){throw (T 'rg.pick')}
        $g=Get-SelectedGroup
        $done=0
        $fails=@()
        foreach($row in $rows){
            try{Move-ProjectToGroup $row.Tag.FullName $g;$done++}catch{$fails+=($row.Text+': '+$_.Exception.Message)}
        }
        $msg=if($g){T 'rg.doneGroup' $done $g}else{T 'rg.doneRoot' $done}
        if($fails.Count){Note ($msg+' '+(T 'sum.skipped' $fails.Count)+"`n`n"+($fails -join "`n`n"))}
        else{$hide.Text=$msg}
    }catch{Note $_.Exception.Message}finally{Load-Folders $source.Text}
}
$regroup.Add_Click({Move-SelectionToGroup})
function Apply-Selection($undo){
    try{
        $rows=@($list.SelectedItems)
        if(!$rows.Count){throw (T 'err.selectFirst')}
        $group=if($undo){''}else{Get-SelectedGroup}
        if(!$testing){
            if(!$undo -and $rows.Count -gt 1){
                $names=(@($rows | Select-Object -First 15) | ForEach-Object {'• '+$_.Text}) -join "`n"
                if($rows.Count -gt 15){$names+="`n…"}
                $q=if($group){T 'bulk.confirmGroup' $rows.Count $names $group}else{T 'bulk.confirm' $rows.Count $names}
                if(!(Ask $q (T 'bulk.title'))){return}
            }
            # Taşımadan önce klasörü kullanan programları göster. Kullanımdaysa taşıma zaten güvenle iptal edilir.
            $busy=@(foreach($row in $rows){
                $users=@(Find-FolderUsers $row.Tag.FullName)
                if($users.Count){$row.Text+":`n  "+($users -join "`n  ")}
            })
            if($busy.Count -and !(Ask (T 'busy.text' ($busy -join "`n")) (T 'busy.title'))){return}
        }
        if(!$undo){
            $probe=[IO.Directory]::CreateDirectory((Join-Path $source.Text ('EnderChest-Test-'+[guid]::NewGuid())))
            try{
                Move-Project $probe
                Restore-Project $probe
            }finally{
                if([IO.Directory]::Exists($probe.FullName) -and !([IO.File]::GetAttributes($probe.FullName) -band [IO.FileAttributes]::ReparsePoint)){[IO.Directory]::Delete($probe.FullName,$false)}
            }
        }
        # Toplu işlemde bir klasör başarısız olursa diğerleri yine işlenir.
        $done=0
        $fails=@()
        foreach($row in $rows){
            try{
                if($undo){Restore-Project $row.Tag}else{Move-Project $row.Tag $group}
                $done++
            }catch{$fails+=($row.Text+': '+$_.Exception.Message)}
        }
        $msg=if($undo){T 'done.restore' $done}elseif($group){T 'done.moveGroup' $done $group}else{T 'done.move' $done}
        if($fails.Count){Note ($msg+' '+(T 'sum.skipped' $fails.Count)+"`n`n"+($fails -join "`n`n"))}
        else{$hide.Text=$msg}
    }catch{Note $_.Exception.Message}finally{Load-Folders $source.Text}
}
$add.Add_Click({Apply-Selection $false})
$restore.Add_Click({Apply-Selection $true})
$open.Add_Click({Invoke-Item -LiteralPath $dir})

# --- Bağlantı sağlığı ---
function Get-ChestHealth {
    $records=@(Get-ProjectRecords)
    $byId=@{}
    $byName=@{}
    foreach($r in $records){if($r.id){$byId[$r.id]=$r.old};if($r.name){$byName[$r.name]=$r.old}}
    $rows=@()
    foreach($entry in @(Get-ChestProjects)){
        if($entry.Name -like 'EnderChest-Test-*'){continue}
        $id='';try{$id=[ChestIdentity]::Read($entry.FullName)}catch{}
        $old=if($id -and $byId.ContainsKey($id)){$byId[$id]}elseif($byName.ContainsKey($entry.Name)){$byName[$entry.Name]}else{Join-Path $desktop $entry.Name}
        $group=if($entry.Parent.FullName -ne $dir){$entry.Parent.Name}else{''}
        $item=Get-Item -LiteralPath $old -Force -ErrorAction SilentlyContinue
        if(Is-Bridge $old $entry.FullName){$state=if(([IO.File]::GetAttributes($old) -band 6) -eq 6){'ok'}else{'visible'}}
        elseif(!$item){$state='missing'}
        elseif($item.LinkType){$state='other-link'}
        else{$state='occupied'}
        $rows+=[pscustomobject]@{Name=$entry.Name;Group=$group;State=$state;Old=$old;Real=$entry.FullName}
    }
    # Hedefi artık olmayan, sandığı gösteren bağlantılar (kimlikten de bulunamayanlar).
    $places=@(@($desktop)+@($records | ForEach-Object {Split-Path $_.old -Parent}) | Select-Object -Unique)
    foreach($place in $places){
        if(![IO.Directory]::Exists($place)){continue}
        foreach($j in @(Get-ChildItem -LiteralPath $place -Directory -Force -ErrorAction SilentlyContinue | Where-Object {$_.LinkType -eq 'Junction'})){
            $t=[string](@($j.Target)[0])
            if($t -and $t.StartsWith($dir+'\',[StringComparison]::OrdinalIgnoreCase) -and ![IO.Directory]::Exists($t)){
                $rows+=[pscustomobject]@{Name=$j.Name;Group='';State='broken';Old=$j.FullName;Real=$t}
            }
        }
    }
    return $rows
}
$healthKey=@{ok='h.ok';visible='h.visible';missing='h.missing';occupied='h.occupied';'other-link'='h.otherLink';broken='h.broken'}
function Repair-Health($r){
    switch($r.State){
        'ok'{return $null}
        'visible'{[IO.File]::SetAttributes($r.Old,([IO.File]::GetAttributes($r.Old) -bor 6));return $null}
        'missing'{
            $parentDir=Split-Path $r.Old -Parent
            if(![IO.Directory]::Exists($parentDir)){throw (T 'err.parentMissing' $parentDir)}
            Assert-Local $r.Real
            New-Bridge $r.Old $r.Real
            if(!(Is-Bridge $r.Old $r.Real)){throw (T 'err.verifyOld')}
            [IO.File]::SetAttributes($r.Old,([IO.File]::GetAttributes($r.Old) -bor 6))
            Set-ProjectRecord $r.Real $r.Old
            return $null
        }
        'broken'{
            $j=Get-Item -LiteralPath $r.Old -Force
            if($j.LinkType -ne 'Junction' -or [IO.Directory]::Exists($r.Real)){throw (T 'err.notBroken')}
            # Yalnız bağlantı silinir; hedefi zaten yok.
            [IO.Directory]::Delete($r.Old,$false)
            return (T 'h.brokenRemoved')
        }
        'occupied'{return (T 'h.occupiedHelp')}
        default{return (T 'h.otherHelp')}
    }
}
function Convert-ToGroup($r){
    # Sandığın kökünde, elle açılmış boş/proje olmayan bir klasörü grup olarak işaretler.
    if($r.State -ne 'missing' -or $r.Group -or (Split-Path $r.Real -Parent) -ne $dir){throw (T 'err.groupOnlyRoot')}
    if(Get-ProjectKind $r.Real){throw (T 'err.looksProject')}
    Set-GroupMarker $r.Real
}
function Show-Health {
    $h=New-Object PixelForm
    $h.Text=T 'h.title'
    $h.Font=$form.Font
    $h.ClientSize='800,520'
    $h.StartPosition='CenterParent'
    $h.FormBorderStyle='FixedDialog'
    $h.MaximizeBox=$false
    $h.MinimizeBox=$false
    $h.ShowInTaskbar=$false
    if($appIcon){$h.Icon=$appIcon}
    $head=New-Object PixelLabel
    $head.Font=[Px]::Display(16)
    $head.Text=(T 'h.title').ToUpper([Globalization.CultureInfo]::GetCultureInfo($script:Lang))
    $head.SetBounds(84,26,690,28)
    $lvHeader=New-Object PixelHeader
    $lvHeader.Font=$bold
    $lvHeader.SetBounds(30,94,740,32)
    $lv=New-Object PixelList
    $lv.SetBounds(30,126,740,248)
    $lv.MultiSelect=$true
    [void]$lv.Columns.Add((T 'h.colProject'),180)
    [void]$lv.Columns.Add((T 'h.colGroup'),110)
    [void]$lv.Columns.Add((T 'h.colState'),210)
    [void]$lv.Columns.Add((T 'h.colOld'),240)
    $lvHeader.List=$lv
    $info=New-Object PixelLabel
    $info.SetBounds(24,392,752,48)
    $info.ForeColor=[Px]::Dim
    $fix=New-Object PixelButton;$fix.Text=T 'h.fix';$fix.Font=$bold;$fix.Variant=1;$fix.SetBounds(24,452,220,46)
    $makeGroup=New-Object PixelButton;$makeGroup.Text=T 'h.makeGroup';$makeGroup.Font=$bold;$makeGroup.SetBounds(254,452,190,46)
    $refresh=New-Object PixelButton;$refresh.Text=T 'h.refresh';$refresh.Font=$bold;$refresh.SetBounds(454,452,150,46)
    $closeBtn=New-Object PixelButton;$closeBtn.Text=T 'h.close';$closeBtn.Font=$bold;$closeBtn.SetBounds(614,452,162,46)
    $h.Controls.AddRange(@($head,$lvHeader,$lv,$info,$fix,$makeGroup,$refresh,$closeBtn))
    $h.Add_Paint({param($s,$e)
        [Px]::Banner($e.Graphics,$h.ClientSize.Width,76)
        [Px]::Chest($e.Graphics,24,10,3)
        [Px]::Slot($e.Graphics,(New-Object Drawing.Rectangle 24,88,752,292))
    })
    $fill={
        # Sandık içinde taşınmış projeleri önce kimlikten bulup yönlendir.
        try{[void](Repair-MovedLinks)}catch{}
        $lv.BeginUpdate()
        $lv.Items.Clear()
        $rows=@(Get-ChestHealth)
        $bad=0
        foreach($r in $rows){
            $it=$lv.Items.Add($r.Name)
            $it.UseItemStyleForSubItems=$false
            $g=$it.SubItems.Add($(if($r.Group){$r.Group}else{'—'}))
            $st=$it.SubItems.Add((T $healthKey[$r.State]))
            $o=$it.SubItems.Add($(if($Snapshot){$r.Old.Replace($desktop,'C:\Users\you\Desktop')}else{$r.Old}))
            $it.Tag=$r
            $col=switch($r.State){'ok'{[Px]::Ok}'visible'{[Px]::Warn}'missing'{[Px]::Warn}'broken'{[Px]::Warn}default{[Px]::Bad}}
            $it.ForeColor=[Px]::Ink
            $g.ForeColor=[Px]::Dim
            $st.ForeColor=$col
            $o.ForeColor=[Px]::Faint
            if($r.State -ne 'ok'){$bad++}
        }
        $lv.EndUpdate()
        $lv.FitColumns()
        $info.Text=if(!$rows.Count){T 'h.empty'}elseif($bad){T 'h.bad' $bad}else{T 'h.allOk' $rows.Count}
    }
    $fix.Add_Click({
        $msgs=@()
        foreach($it in @($lv.SelectedItems)){
            try{$m=Repair-Health $it.Tag;if($m){$msgs+=($it.Text+': '+$m)}}catch{$msgs+=($it.Text+': '+$_.Exception.Message)}
        }
        & $fill
        if($msgs.Count){[void][PixelDialog]::Show($h,(T 'h.title'),($msgs -join "`n`n"),[string[]]@((T 'dlg.ok')),0)}
    })
    $makeGroup.Add_Click({
        $msgs=@()
        $made=0
        foreach($it in @($lv.SelectedItems)){
            try{Convert-ToGroup $it.Tag;$made++}catch{$msgs+=($it.Text+': '+$_.Exception.Message)}
        }
        & $fill
        if($made){Refresh-Groups}
        if($msgs.Count){[void][PixelDialog]::Show($h,(T 'h.title'),($msgs -join "`n`n"),[string[]]@((T 'dlg.ok')),0)}
    })
    $refresh.Add_Click({& $fill})
    $closeBtn.Add_Click({$h.Close()})
    & $fill
    [void]$h.ShowDialog($form)
    $h.Dispose()
}
$healthBtn.Add_Click({try{Show-Health}catch{Note $_.Exception.Message}})

# --- Tepsi ve başlangıç ---
$trayIcon=$null
$trayMenu=$null
function Show-Panel {
    if(!$form.Visible){$form.Show()}
    if($form.WindowState -eq 'Minimized'){$form.WindowState='Normal'}
    $form.Activate()
    try{Load-Folders $source.Text}catch{}
}
function Notify-User($msg){
    $hide.Text=$msg
    if($trayIcon -and !$form.Visible){$trayIcon.ShowBalloonTip(4000,'Ender Chest',$msg,'Info')}
}
$runKey='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$launcher=Join-Path $PSScriptRoot 'EnderChest.exe'
function Get-Autostart {
    try{return [bool](Get-ItemProperty -Path $runKey -Name 'Ender Chest' -ErrorAction Stop).'Ender Chest'}catch{return $false}
}
function Set-Autostart($on){
    if($on){Set-ItemProperty -Path $runKey -Name 'Ender Chest' -Value ('"'+$launcher+'" --tray')}
    else{Remove-ItemProperty -Path $runKey -Name 'Ender Chest' -ErrorAction SilentlyContinue}
}
. (Join-Path $PSScriptRoot 'DesktopMonitor.ps1')
Refresh-Groups
Load-Folders $desktop
if($IntegrationTest){
    Check-DesktopSupport
    $f=[IO.Directory]::CreateDirectory((Join-Path $desktop 'Türkçe Proje'))
    Index-Desktop
    $dest=Join-Path $dir $f.Name
    [IO.Directory]::Move($f.FullName,$dest)
    Sync-Chest
    if(!(Is-Bridge $f.FullName $dest)){throw 'Explorer move bridge'}
    [IO.File]::WriteAllText((Join-Path $f.FullName 'kod.txt'),'değişiklik')
    if([IO.File]::ReadAllText((Join-Path $dest 'kod.txt')) -cne 'değişiklik'){throw 'Write through'}
    Restore-Project $f
    if(!(Test-Path -LiteralPath (Join-Path $f.FullName 'kod.txt')) -or [IO.Directory]::Exists($dest)){throw 'Undo'}
    [IO.Directory]::Move($f.FullName,$dest)
    Repair-DesktopPath (Get-Item -LiteralPath $dest)
    if(([IO.File]::GetAttributes($f.FullName) -band 6) -ne 6){throw 'Desktop visibility'}
    if(([IO.File]::GetAttributes($dest) -band 6) -ne 0){throw 'Real project attributes'}
    Load-Folders $desktop
    if(@($list.Items | Where-Object {$_.Tag.FullName -eq $f.FullName}).Count -ne 1){throw 'Restore list'}
    Restore-Project $f
    'PASS: move, edit, restore, repair, visibility'
    return
}
if($MonitorTest){
    $project=[IO.Directory]::CreateDirectory((Join-Path $desktop 'Çağrı [test]'))
    Index-Desktop
    $id=[ChestIdentity]::Read($project.FullName)
    $dest=Join-Path $dir $project.Name
    [IO.Directory]::Move($project.FullName,$dest)
    if([ChestIdentity]::Read($dest) -ne $id){throw 'Move identity'}
    $collision=[IO.Directory]::CreateDirectory($project.FullName)
    Sync-Chest
    if(!$reported.ContainsKey($id) -or !(Test-Path -LiteralPath $dest) -or [ChestIdentity]::Read($collision.FullName) -eq $id){throw 'Collision protection'}
    try{Repair-DesktopPath (Get-Item -LiteralPath $dest);throw 'Unexpected repair'}catch{if($_.Exception.Message -notlike 'Eski konum dolu*'){throw}}
    'PASS: identity, collision, repair collision'
    return
}
if($SafetyTest){
    $pending={@([IO.Directory]::GetFiles((Get-StateDir),'pending-*.json')).Count}
    # 1. Taşıma tam ortada kesildi: proje sandıkta, eski yol yok.
    $a=[IO.Directory]::CreateDirectory((Join-Path $desktop 'Yarım Taşıma'))
    $aOld=$a.FullName
    $aDest=Join-Path $dir $a.Name
    [IO.File]::WriteAllText((Join-Path $aOld 'not.txt'),'veri')
    [void](Start-Journal 'move' $aOld $aDest)
    [IO.Directory]::Move($aOld,$aDest)
    $m=@(Resume-Journal)
    if(!(Is-Bridge $aOld $aDest) -or (& $pending) -ne 0 -or $m.Count -ne 1){throw 'Journal move resume'}
    if([IO.File]::ReadAllText((Join-Path $aOld 'not.txt')) -ne 'veri'){throw 'Journal move data'}
    # 2. Geri taşıma tam ortada kesildi: bağlantı silinmiş, proje hâlâ sandıkta.
    [void](Start-Journal 'restore' $aOld $aDest)
    [IO.Directory]::Delete($aOld,$false)
    $m=@(Resume-Journal)
    if(!(Test-RealFolder $aOld) -or [IO.Directory]::Exists($aDest) -or (& $pending) -ne 0){throw 'Journal restore resume'}
    # 3. Bozuk günlük dosyalara dokunulmadan temizlenir.
    [IO.File]::WriteAllText((Join-Path (Get-StateDir) 'pending-bozuk.json'),'{yarım')
    $m=@(Resume-Journal)
    if((& $pending) -ne 0 -or !(Test-RealFolder $aOld)){throw 'Journal corrupt'}
    # 4. Kullanımdaki klasör: taşıma hiçbir şeyi değiştirmeden iptal edilir.
    $h=[IO.File]::Open((Join-Path $aOld 'not.txt'),'Open','ReadWrite','Read')
    try{
        try{Move-Project (Get-Item -LiteralPath $aOld);throw 'Locked move succeeded'}catch{if($_.Exception.Message -notlike 'Klasör kullanımda*'){throw}}
    }finally{$h.Dispose()}
    if(!(Test-RealFolder $aOld) -or (Test-Path -LiteralPath $aDest) -or (& $pending) -ne 0){throw 'Locked move rollback'}
    # 5. Sandıkta aynı adlı öğe varsa iki tarafa da dokunulmaz.
    [void][IO.Directory]::CreateDirectory($aDest)
    try{Move-Project (Get-Item -LiteralPath $aOld);throw 'Name collision move'}catch{if($_.Exception.Message -notlike 'Sandıkta aynı adlı*'){throw}}
    if(!(Test-RealFolder $aOld)){throw 'Name collision source'}
    [IO.Directory]::Delete($aDest,$false)
    # 6. Panel kapalıyken yapılan taşıma, diske kaydedilen dizinden tanınır.
    Index-Desktop
    $known.Clear();$seen.Clear()
    Load-MonitorState
    if(!$known.ContainsValue($aOld)){throw 'Index persisted'}
    [IO.Directory]::Move($aOld,$aDest)
    Sync-Chest
    if(!(Is-Bridge $aOld $aDest)){throw 'Persisted index bridge'}
    # 7. Durum dosyaları tekrar tekrar yazılabilir (üzerine yazma).
    Write-StateFile 'deneme.json' @{n=1}
    Write-StateFile 'deneme.json' @{n=2}
    if((Read-StateFile 'deneme.json').n -ne 2){throw 'State overwrite'}
    # 8. Durum klasörü proje gibi görünmez.
    if(@(Get-PlainFolders $dir | Where-Object {$_.Name -eq '.enderchest'}).Count){throw 'State folder visible'}
    Restore-Project (Get-Item -LiteralPath $aOld -Force)
    if(!(Test-RealFolder $aOld) -or [IO.File]::ReadAllText((Join-Path $aOld 'not.txt')) -ne 'veri'){throw 'Final restore'}
    'PASS: journal move/restore/corrupt, lock, name collision, persisted index, hidden state'
    return
}
if($LangTest){
    # Her dil İngilizce ile aynı anahtarlara ve aynı yer tutuculara sahip olmalı;
    # Latin/Kiril dillerinin tüm karakterleri piksel fontta bulunmalı.
    Add-Type -AssemblyName PresentationCore
    $glyphs=(New-Object Windows.Media.GlyphTypeface([uri](Join-Path $PSScriptRoot 'fonts\PixelifySans-Regular.ttf'))).CharacterToGlyphMap
    $problems=@()
    foreach($code in $Languages.Keys){
        if(!$Strings.ContainsKey($code)){$problems+="${code}: table missing";continue}
        foreach($k in $Strings.en.Keys){
            $s=$Strings[$code][$k]
            if($null -eq $s){$problems+="$code/$k missing";continue}
            $want=@([regex]::Matches($Strings.en[$k],'\{\d\}') | ForEach-Object Value | Sort-Object -Unique)
            $have=@([regex]::Matches($s,'\{\d\}') | ForEach-Object Value | Sort-Object -Unique)
            if(($want -join ',') -ne ($have -join ',')){$problems+="$code/$k placeholders [$($have -join ',')] != [$($want -join ',')]"}
            if($code -notin 'ja','zh'){
                $drawn=[Px]::Glyphs($s,[Px]::Body(16))
                $miss=@($drawn.ToCharArray() | Where-Object {[int]$_ -ge 32 -and !$glyphs.ContainsKey([int]$_)} | Select-Object -Unique)
                if($miss.Count){$problems+="$code/$k glyphs missing: $($miss -join '')"}
            }
        }
        foreach($k in $Strings[$code].Keys){if(!$Strings.en.ContainsKey($k)){$problems+="$code/$k unknown key"}}
    }
    if($problems.Count){throw ("Language problems:`n"+($problems -join "`n"))}
    # Arayüz her dilde kurulabilmeli.
    foreach($code in $Languages.Keys){Set-Language $code;Apply-Language}
    Set-Language 'tr'
    "PASS: $($Languages.Count) languages, $($Strings.en.Count) keys, placeholders, pixel-font glyphs, live switch"
    return
}
if($GroupTest){
    [void]$list.Handle
    # 1. Grup oluşturma: işaretli, proje sayılmaz, seçicide görünür
    $web=New-Group 'Web'
    if(!(Test-Group $web) -or @(Get-Groups).Count -ne 1){throw 'Group create'}
    if(@(Get-ChestProjects | Where-Object {$_.FullName -eq $web}).Count){throw 'Group listed as project'}
    Refresh-Groups
    if($groupBox.Items.IndexOf('Web') -lt 1){throw 'Group picker'}
    try{[void](New-Group 'a/b');throw 'Bad group name accepted'}catch{if($_.Exception.Message -notlike 'Bu ad*'){throw}}
    # 2. Doğrudan gruba taşıma
    $p1=[IO.Directory]::CreateDirectory((Join-Path $desktop 'site-bir'))
    [IO.File]::WriteAllText((Join-Path $p1.FullName 'index.html'),'ilk')
    $p1Old=$p1.FullName
    Move-Project $p1 'Web'
    $inWeb=Join-Path $web 'site-bir'
    if(!(Is-Bridge $p1Old $inWeb)){throw 'Move into group'}
    [IO.File]::WriteAllText((Join-Path $p1Old 'index.html'),'iki')
    if([IO.File]::ReadAllText((Join-Path $inWeb 'index.html')) -ne 'iki'){throw 'Group write-through'}
    Load-Folders $desktop
    $row=@($list.Items | Where-Object {$_.Text -eq 'site-bir'})
    if($row.Count -ne 1 -or $row[0].SubItems[2].Text -ne 'Sandıkta · Web'){throw ('Group status: '+$row[0].SubItems[2].Text)}
    # 3. Explorer ile gruptan köke sürükleme: bağlantı kimlikten yeniden yönlendirilir
    $atRoot=Join-Path $dir 'site-bir'
    [IO.Directory]::Move($inWeb,$atRoot)
    $fixed=@(Repair-MovedLinks)
    if($fixed -notcontains 'site-bir' -or !(Is-Bridge $p1Old $atRoot)){throw 'Explorer regroup'}
    # 4. Sandıkta yeniden adlandırma: eski yol yine çalışır
    $renamed=Join-Path $web 'site-bir-yeni'
    [IO.Directory]::Move($atRoot,$renamed)
    [void](Repair-MovedLinks)
    if(!(Is-Bridge $p1Old $renamed) -or [IO.File]::ReadAllText((Join-Path $p1Old 'index.html')) -ne 'iki'){throw 'Rename in chest'}
    # 5. Panelden gruba taşıma (köke)
    Move-ProjectToGroup $p1Old ''
    $back=Join-Path $dir 'site-bir-yeni'
    if(!(Is-Bridge $p1Old $back) -or [IO.Directory]::Exists($renamed)){throw 'Panel regroup'}
    # 6. Yarıda kalan grup taşıması açılışta tamamlanır
    $half=Join-Path $web 'site-bir-yeni'
    [void](Start-Journal 'move' $p1Old $half)
    [IO.Directory]::Move($back,$half)
    $m=@(Resume-Journal)
    if(!(Is-Bridge $p1Old $half) -or $m.Count -ne 1){throw 'Resume regroup'}
    # 7. Masaüstünden Explorer ile doğrudan grubun içine bırakma
    $p2=[IO.Directory]::CreateDirectory((Join-Path $desktop 'api'))
    $p2Old=$p2.FullName
    Index-Desktop
    [IO.Directory]::Move($p2Old,(Join-Path $web 'api'))
    Sync-Chest
    if(!(Is-Bridge $p2Old (Join-Path $web 'api'))){throw 'Explorer drop into group'}
    # 8. Ad benzersizliği: başka grupta aynı adlı proje varken taşıma yapılmaz
    $dup=[IO.Directory]::CreateDirectory((Join-Path $desktop 'api-kopya'))
    [void][IO.Directory]::CreateDirectory((Join-Path $web 'api-kopya'))
    try{Move-Project $dup;throw 'Duplicate name moved'}catch{if($_.Exception.Message -notlike 'Sandıkta aynı adlı*'){throw}}
    if(!(Test-RealFolder $dup.FullName)){throw 'Duplicate source kept'}
    [IO.Directory]::Delete((Join-Path $web 'api-kopya'),$false)
    # 9. Eksik yol sorusu: grup ve kayıtlı projeler sorulmaz, elle açılmış klasör sorulur
    $loose=[IO.Directory]::CreateDirectory((Join-Path $dir 'Arşiv'))
    $ask=@(Get-UnmatchedProjects | ForEach-Object {$_.Entry.Name})
    if(($ask -join '|') -ne 'Arşiv'){throw ('Unmatched: '+($ask -join '|'))}
    $r=@(Get-ChestHealth) | Where-Object {$_.Name -eq 'Arşiv'}
    Convert-ToGroup $r
    if(!(Test-Group $loose.FullName) -or @(Get-UnmatchedProjects).Count){throw 'Convert to group'}
    # 10. Eski sürüm bağlantısı kayda alınır
    $legacy=[IO.Directory]::CreateDirectory((Join-Path $dir 'eski-proje'))
    New-Bridge (Join-Path $desktop 'eski-proje') $legacy.FullName
    Register-ExistingLinks
    if(!@(Get-ProjectRecords | Where-Object {$_.old -eq (Join-Path $desktop 'eski-proje') -and $_.id}).Count){throw 'Register legacy'}
    # 11. Sağlık ekranı grup bilgisini gösterir, gruptaki proje geri taşınabilir
    $api=@(Get-ChestHealth) | Where-Object {$_.Name -eq 'api'}
    if($api.Group -ne 'Web' -or $api.State -ne 'ok'){throw 'Health group'}
    Restore-Project (Get-Item -LiteralPath $p2Old -Force)
    if(!(Test-RealFolder $p2Old) -or [IO.Directory]::Exists((Join-Path $web 'api')) -or @(Get-ProjectRecords | Where-Object {$_.old -eq $p2Old}).Count){throw 'Restore from group'}
    'PASS: groups create/pick, move into group, explorer regroup, rename, panel regroup, resume, explorer drop, unique names, unmatched, convert, legacy register, health, restore'
    return
}
if($FeatureTest){
    [void]$list.Handle
    # 1. Proje türü algılama
    $node=[IO.Directory]::CreateDirectory((Join-Path $desktop 'node-app'))
    [IO.File]::WriteAllText((Join-Path $node.FullName 'package.json'),'{}')
    [void][IO.Directory]::CreateDirectory((Join-Path $node.FullName '.git'))
    $plain=[IO.Directory]::CreateDirectory((Join-Path $desktop 'Fotoğraflar'))
    $tool=[IO.Directory]::CreateDirectory((Join-Path $desktop 'araç'))
    [IO.File]::WriteAllText((Join-Path $tool.FullName 'Arac.csproj'),'')
    $skip=[IO.Directory]::CreateDirectory((Join-Path $desktop 'eski-site'))
    [IO.File]::WriteAllText((Join-Path $skip.FullName 'index.html'),'')
    if((Get-ProjectKind $node.FullName) -ne 'Node, Git'){throw ('Kind node: '+(Get-ProjectKind $node.FullName))}
    if(Get-ProjectKind $plain.FullName){throw 'Kind plain'}
    if((Get-ProjectKind $tool.FullName) -ne '.NET'){throw 'Kind dotnet'}
    # 2. Hariç tutma ve toplu seçim
    Save-Settings @{excluded=@($skip.FullName)}
    Load-Folders $desktop
    [void](Select-Projects)
    $sel=@($list.SelectedItems | ForEach-Object {$_.Text} | Sort-Object)
    if(($sel -join '|') -ne 'araç|node-app'){throw ('Bulk select: '+($sel -join '|'))}
    # 3. Toplu taşıma: kullanımdaki klasör atlanır, diğeri yine taşınır
    $h=[IO.File]::Open((Join-Path $node.FullName 'package.json'),'Open','ReadWrite','Read')
    try{Apply-Selection $false}finally{$h.Dispose()}
    $toolDest=Join-Path $dir $tool.Name
    if(!(Is-Bridge $tool.FullName $toolDest)){throw 'Bulk moved other'}
    if(!(Test-RealFolder $node.FullName) -or $script:lastNote -notlike '1 klasör sandığa taşındı. 1 klasör atlandı*'){throw ('Bulk partial: '+$script:lastNote)}
    # 4. Proje kaydı
    $rec=@(Get-ProjectRecords | Where-Object {$_.old -eq $tool.FullName})
    if($rec.Count -ne 1 -or !$rec[0].id -or $rec[0].name -ne 'araç'){throw 'Project record'}
    # 5. Sağlık: bağlı / görünür / eksik / kırık
    $state={param($n) (@(Get-ChestHealth) | Where-Object {$_.Name -eq $n} | Select-Object -First 1)}
    if((& $state 'araç').State -ne 'ok'){throw 'Health ok'}
    [IO.File]::SetAttributes($tool.FullName,([IO.File]::GetAttributes($tool.FullName) -band (-bnot 6)))
    $r=& $state 'araç'
    if($r.State -ne 'visible'){throw 'Health visible'}
    [void](Repair-Health $r)
    if((& $state 'araç').State -ne 'ok'){throw 'Health visible fix'}
    [IO.Directory]::Delete($tool.FullName,$false)
    $r=& $state 'araç'
    if($r.State -ne 'missing'){throw 'Health missing'}
    [void](Repair-Health $r)
    if((& $state 'araç').State -ne 'ok'){throw 'Health missing fix'}
    [IO.File]::WriteAllText((Join-Path $toolDest 'kod.cs'),'veri')
    [IO.Directory]::Move($toolDest,(Join-Path $dir 'araç2'))
    $r=@(Get-ChestHealth) | Where-Object {$_.State -eq 'broken'} | Select-Object -First 1
    if(!$r -or $r.Old -ne $tool.FullName){throw 'Health broken'}
    [void](Repair-Health $r)
    if(Get-Item -LiteralPath $tool.FullName -Force -ErrorAction SilentlyContinue){throw 'Broken link removed'}
    if([IO.File]::ReadAllText((Join-Path $dir 'araç2\kod.cs')) -ne 'veri'){throw 'Broken repair kept data'}
    # 6. Durum klasörü proje gibi görünmez, tek klasörlük normal geri taşıma çalışır
    Load-Folders $desktop
    if(@($list.Items | Where-Object {$_.Text -eq '.enderchest'}).Count){throw 'State listed'}
    'PASS: project kinds, exclusions, bulk select, partial bulk move, records, health ok/visible/missing/broken'
    return
}
if($Demo){
    # Ekran görüntüsü / deneme modu: geçici bir masaüstünde örnek projelerle açılır, gerçek dosyalara dokunmaz.
    $samples=[ordered]@{
        'portfolio-site'=@('package.json','.git','index.html');'api-server'=@('go.mod','.git');'ml-notebooks'=@('requirements.txt')
        'game-jam'=@('Game.sln');'mobile-app'=@('pubspec.yaml','.git');'Photos'=@();'Invoices 2026'=@();'rust-cli'=@('Cargo.toml','.git')
    }
    foreach($name in $samples.Keys){
        $d=[IO.Directory]::CreateDirectory((Join-Path $desktop $name))
        foreach($m in $samples[$name]){if($m -like '.*'){[void][IO.Directory]::CreateDirectory((Join-Path $d.FullName $m))}else{[IO.File]::WriteAllText((Join-Path $d.FullName $m),'')}}
    }
    [void](New-Group 'Web')
    Move-Project (Get-Item -LiteralPath (Join-Path $desktop 'portfolio-site')) 'Web'
    Move-Project (Get-Item -LiteralPath (Join-Path $desktop 'api-server'))
    Refresh-Groups
    Load-Folders $desktop
    foreach($row in $list.Items){if($row.Text -in 'ml-notebooks','mobile-app'){$row.Selected=$true}}
    $hide.Text=T 'status.watching'
    # Ekran görüntüsünde kullanıcı adı görünmesin.
    if($Snapshot){$source.Text='C:\Users\you\Desktop'}
    if($Snapshot){
        # Yalnız kendi penceresini kaydeder: pencere en üstte tutulur, ekranın başka yeri alınmaz.
        $form.TopMost=$true
        $shot=New-Object Windows.Forms.Timer
        $shot.Interval=1800
        $shot.Add_Tick({
            $shot.Stop()
            $target=@([Windows.Forms.Application]::OpenForms)[-1]
            $area=$target.RectangleToScreen($target.ClientRectangle)
            $b=New-Object Drawing.Bitmap $area.Width,$area.Height
            $g=[Drawing.Graphics]::FromImage($b)
            $g.CopyFromScreen($area.Location,[Drawing.Point]::Empty,$area.Size)
            $b.Save($Snapshot,[Drawing.Imaging.ImageFormat]::Png)
            $g.Dispose();$b.Dispose()
            if($target -ne $form){$target.Close()}
            $form.Close()
        })
        $form.Add_Shown({$shot.Start()})
    }
    if($DemoDialog){
        # Diyalogları da göstermek için: lang | health | confirm
        $form.Add_Shown({$form.BeginInvoke([Action]{
            switch($DemoDialog){
                'lang'{[void][PixelDialog]::Choose($form,'Language · Dil · Sprache · Idioma',(T 'lang.text'),[string[]]@($Languages.Values),[array]::IndexOf(@($Languages.Keys),$script:Lang))}
                'health'{Show-Health}
                'confirm'{[void](Ask (T 'bulk.confirm' 2 "• ml-notebooks`n• mobile-app") (T 'bulk.title'))}
            }
        })})
    }
    $form.Add_Shown({$form.Activate()})
    [Windows.Forms.Application]::Run($form)
    return
}
if($testing){
    $folder=[IO.Directory]::CreateDirectory((Join-Path $desktop 'Öğrenci İşleri'))
    $old=$folder.FullName
    $dest=Join-Path $dir $folder.Name
    [IO.File]::WriteAllText("$old\çağrı.txt",'ilk')
    try{Move-Project $folder}catch{
        if([IO.File]::ReadAllText("$old\çağrı.txt") -ne "ilk" -or [IO.Directory]::Exists($dest)){throw "Rollback failed"}
        Write-Output "Rollback verified"
        throw
    }
    if(!(Is-Bridge $old $dest) -or !([IO.File]::GetAttributes($old) -band 2)){throw 'Bridge'}
    [IO.File]::WriteAllText("$old\çağrı.txt",'son')
    if([IO.File]::ReadAllText("$dest\çağrı.txt") -ne 'son'){throw 'Write'}
    Load-Folders $desktop
    if($list.Items.Count -ne 1){throw 'Restore list'}
    Restore-Project $folder
    if((Test-Path -LiteralPath $dest) -or [IO.File]::ReadAllText("$old\çağrı.txt") -ne 'son'){throw 'Restore'}
    'PASS'
}else{
    # Tek kopya kilidi ve dil seçimi arayüzden önce yapıldı ($mutex, $showEvent).
    try{
        try{
            $recovered=@(Resume-Journal)
            if($recovered.Count){Note ((T 'start.recovered')+"`n`n"+($recovered -join "`n`n"))}
        }catch{Note ((T 'start.recoverFailed')+"`n"+$_.Exception.Message)}
        try{Check-DesktopSupport}catch{Note ((T 'start.unsupported')+"`n"+$_.Exception.Message);return}
        Load-MonitorState
        # Eski sürümlerde kurulan bağlantıları kayda al, sandık içinde taşınmış projeleri yeniden yönlendir.
        try{Register-ExistingLinks}catch{}
        $redirected=@()
        try{$redirected=@(Repair-MovedLinks)}catch{Note ((T 'start.redirectFailed')+"`n"+$_.Exception.Message)}
        Index-Desktop
        Refresh-Groups
        Load-Folders $desktop
        # Tepsi simgesi ve menüsü (piksel temalı)
        $trayIcon=New-Object Windows.Forms.NotifyIcon
        $trayIcon.Icon=if($appIcon){$appIcon}else{[Drawing.SystemIcons]::Application}
        $trayIcon.Text=T 'tray.watching'
        $trayMenu=New-Object Windows.Forms.ContextMenuStrip
        $trayMenu.Renderer=New-Object PixelMenuRenderer
        $trayMenu.Font=$form.Font
        $trayMenu.ShowImageMargin=$false
        $miOpen=$trayMenu.Items.Add((T 'tray.open'))
        $miOpen.Font=$bold
        $miChest=$trayMenu.Items.Add((T 'tray.chest'))
        $miHealth=$trayMenu.Items.Add((T 'tray.health'))
        [void]$trayMenu.Items.Add('-')
        $miExit=$trayMenu.Items.Add((T 'tray.exit'))
        $miOpen.Add_Click({Show-Panel})
        $miChest.Add_Click({Invoke-Item -LiteralPath $dir})
        $miHealth.Add_Click({try{Show-Panel;Show-Health}catch{Note $_.Exception.Message}})
        $miExit.Add_Click({$script:exiting=$true;$form.Close()})
        $trayIcon.ContextMenuStrip=$trayMenu
        $trayIcon.Add_MouseClick({param($s,$e) if($e.Button -eq 'Left'){Show-Panel}})
        $trayIcon.Add_BalloonTipClicked({try{Show-Panel;if($script:lastBad){Show-Health}}catch{}})
        $trayIcon.Visible=$true
        $hide.Text=if($redirected.Count){T 'status.redirected' ($redirected -join ', ')}else{T 'status.watching'}
        # Windows ile başlat
        $autostart.Enabled=[IO.File]::Exists($launcher)
        $autostart.Checked=Get-Autostart
        if($autostart.Checked -and $autostart.Enabled){Set-Autostart $true}
        $autostart.Add_CheckedChanged({try{Set-Autostart $autostart.Checked}catch{Note $_.Exception.Message}})
        $script:exiting=$false
        $script:hintShown=$false
        $script:lastBad=0
        $script:tick=0
        # Kapat düğmesi uygulamayı kapatmaz, tepsiye gizler. Çıkış tepsi menüsündedir.
        $form.Add_FormClosing({param($s,$e)
            if(!$script:exiting -and $e.CloseReason -eq 'UserClosing'){
                $e.Cancel=$true
                $form.Hide()
                if(!$script:hintShown){
                    $script:hintShown=$true
                    $trayIcon.ShowBalloonTip(4000,'Ender Chest',(T 'tray.hint'),'Info')
                }
            }
        })
        if($Tray){
            # Windows açılışında: pencere göstermeden doğrudan tepside başla.
            $form.Opacity=0
            $form.ShowInTaskbar=$false
            $form.Add_Shown({$form.Hide();$form.Opacity=1;$form.ShowInTaskbar=$true})
        }else{
            # Başlatıcı gizli konsolla açtığı için Windows ilk pencereyi küçültülmüş gösterebilir: normale al ve öne getir.
            $form.Add_Shown({
                $form.WindowState='Normal'
                $form.TopMost=$true
                $form.Activate()
                $form.TopMost=$false
            })
        }
        $timer=New-Object Windows.Forms.Timer
        $timer.Interval=800
        $timer.Add_Tick({
            $timer.Stop()
            try{
                if($showEvent.WaitOne(0)){Show-Panel}
                # Explorer ile gruplar arasında taşınan / sandıkta yeniden adlandırılan projeler.
                $moved=@(Repair-MovedLinks)
                if($moved.Count){
                    Notify-User (T 'status.redirected' ($moved -join ', '))
                    if($form.Visible){Load-Folders $source.Text}
                }
                Sync-Chest
                Review-Unmatched
                # Yaklaşık dakikada bir bağlantı sağlığını kontrol et.
                $script:tick++
                if($script:tick % 75 -eq 1){
                    $bad=@(Get-ChestHealth | Where-Object {$_.State -ne 'ok'}).Count
                    $trayIcon.Text=if($bad){T 'tray.problems' $bad}else{T 'tray.watching'}
                    if($bad -gt $script:lastBad){$trayIcon.ShowBalloonTip(5000,'Ender Chest',(T 'tray.problemsBalloon' $bad),'Warning')}
                    $script:lastBad=$bad
                }
            }catch{$hide.Text=T 'status.monitorError' $_.Exception.Message}finally{$timer.Start()}
        })
        $timer.Start()
        [Windows.Forms.Application]::Run($form)
    }finally{
        if($timer){$timer.Stop();$timer.Dispose()}
        if($trayIcon){$trayIcon.Visible=$false;$trayIcon.Dispose()}
        $mutex.ReleaseMutex();$mutex.Dispose()
        $showEvent.Dispose()
    }
}
