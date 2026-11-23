# Index only direct desktop folders, never files or a reparse target.
Add-Type -Path (Join-Path $PSScriptRoot 'ChestIdentity.cs')
$known=@{}
$seen=@{}
$reported=@{}
$reviewed=@{}
$script:stateDirty=$false
$groupMarker='.enderchest-group'
function Get-PlainFolders($parentPath){
    Get-ChildItem -LiteralPath $parentPath -Directory -Force | Where-Object {
        $_.FullName -ne $dir -and !($_.Attributes -band ([IO.FileAttributes]::System -bor [IO.FileAttributes]::ReparsePoint))
    }
}

# --- Gruplar: sandığın içinde, gizli işaret dosyası taşıyan klasörler (tek seviye) ---
function Test-Group($path){return [IO.File]::Exists((Join-Path $path $groupMarker))}
function Get-Groups {return @(Get-PlainFolders $dir | Where-Object {Test-Group $_.FullName} | Sort-Object Name)}
function Get-ChestProjects {
    # Sandığın kökündeki projeler + grupların içindeki projeler. Grup klasörleri proje sayılmaz.
    foreach($e in @(Get-PlainFolders $dir)){
        if(Test-Group $e.FullName){foreach($c in @(Get-PlainFolders $e.FullName)){$c}}else{$e}
    }
}
function Get-GroupPath($group){
    if(!$group){return $dir}
    $p=Join-Path $dir $group
    if(!(Test-Group $p)){throw (T 'err.groupMissing' $group)}
    return $p
}
function Set-GroupMarker($path){
    $m=Join-Path $path $groupMarker
    if(![IO.File]::Exists($m)){
        [IO.File]::WriteAllText($m,'Ender Chest group folder. If you delete this file, the folder is treated as a project.')
        [IO.File]::SetAttributes($m,'Hidden')
    }
}
function New-Group($name){
    $name=([string]$name).Trim()
    if(!$name){throw (T 'err.groupEmpty')}
    if($name.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or $name.StartsWith('.') -or $name -like 'EnderChest-Test-*'){throw (T 'err.groupBadName')}
    $path=Join-Path $dir $name
    if(Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue){
        if(Test-Group $path){return $path}
        throw (T 'err.groupExists')
    }
    [void][IO.Directory]::CreateDirectory($path)
    Set-GroupMarker $path
    return $path
}
function Get-ChestTarget($path){
    # Yol, sandığın içindeki var olan bir projeyi gösteren bağlantıysa hedefini döndürür.
    $j=Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    if(!$j -or $j.LinkType -ne 'Junction'){return $null}
    $t=[string](@($j.Target)[0])
    if($t.StartsWith($dir+'\',[StringComparison]::OrdinalIgnoreCase) -and (Test-RealFolder $t)){return $t}
    return $null
}

# --- Proje kaydı: eski yol + klasör kimliği. Sandık içinde taşınan/yeniden adlandırılan projeler kimlikten bulunur ---
function Get-ProjectRecords {
    $list=@()
    $s=Read-StateFile 'projects.json'
    if(!$s){return $list}
    if($s.PSObject.Properties['items']){
        foreach($r in @($s.items)){if($r -and $r.old){$list+=[pscustomobject]@{id=[string]$r.id;name=[string]$r.name;old=[string]$r.old}}}
    }else{
        # 3.2'nin ilk biçimi: { "ad": "eski yol" }
        foreach($p in $s.PSObject.Properties){if($p.Value){$list+=[pscustomobject]@{id='';name=$p.Name;old=[string]$p.Value}}}
    }
    return $list
}
function Save-ProjectRecords($list){Write-StateFile 'projects.json' @{v=2;items=@($list)}}
function Set-ProjectRecord($real,$old){
    # Kayıt yardımcıdır: yazılamazsa taşıma işlemi bozulmaz.
    $name=[IO.Path]::GetFileName($real)
    if($name -like 'EnderChest-Test-*'){return}
    try{
        $id='';try{$id=[ChestIdentity]::Read($real)}catch{}
        $list=@(Get-ProjectRecords | Where-Object {$_.old -ne $old -and (!$id -or $_.id -ne $id)})
        $list+=[pscustomobject]@{id=$id;name=$name;old=$old}
        Save-ProjectRecords $list
    }catch{}
}
function Remove-ProjectRecord($old){
    try{Save-ProjectRecords @(Get-ProjectRecords | Where-Object {$_.old -ne $old})}catch{}
}
function Register-ExistingLinks {
    # Kayıt tutulmadan önce (3.1) oluşturulmuş bağlantıları kayda alır.
    $records=@(Get-ProjectRecords)
    foreach($j in @(Get-ChildItem -LiteralPath $desktop -Directory -Force -ErrorAction SilentlyContinue | Where-Object {$_.LinkType -eq 'Junction'})){
        $t=Get-ChestTarget $j.FullName
        if(!$t){continue}
        $r=@($records | Where-Object {$_.old -eq $j.FullName})
        if(!$r.Count -or !$r[0].id){Set-ProjectRecord $t $j.FullName}
    }
}
function Repair-MovedLinks {
    # Sandık içinde gruba taşınan, gruptan çıkarılan veya yeniden adlandırılan projelerin
    # eski yollarını kimlikten bulup yeni konuma yönlendirir.
    $fixed=@()
    $records=@(Get-ProjectRecords)
    if(!$records.Count){return $fixed}
    $byId=$null
    foreach($r in $records){
        $j=Get-Item -LiteralPath $r.old -Force -ErrorAction SilentlyContinue
        if(!$j -or $j.LinkType -ne 'Junction'){continue}
        $t=[string](@($j.Target)[0])
        if([IO.Directory]::Exists($t) -or !$t.StartsWith($dir+'\',[StringComparison]::OrdinalIgnoreCase)){continue}
        if($null -eq $byId){
            $byId=@{}
            foreach($p in @(Get-ChestProjects)){try{$byId[[ChestIdentity]::Read($p.FullName)]=$p.FullName}catch{}}
        }
        $new=$null
        if($r.id -and $byId.ContainsKey($r.id)){$new=$byId[$r.id]}
        elseif(!$r.id){
            $same=@(Get-ChestProjects | Where-Object {$_.Name -eq [IO.Path]::GetFileName($t)})
            if($same.Count -eq 1){$new=$same[0].FullName}
        }
        if(!$new){continue}
        $journal=Start-Journal 'move' $r.old $new
        [IO.Directory]::Delete($r.old,$false)
        New-Bridge $r.old $new
        if(!(Is-Bridge $r.old $new)){throw (T 'err.retargetPath' $r.old)}
        [IO.File]::SetAttributes($r.old,([IO.File]::GetAttributes($r.old) -bor 6))
        Stop-Journal $journal
        Set-ProjectRecord $new $r.old
        $fixed+=[IO.Path]::GetFileName($r.old)
    }
    return $fixed
}

# Masaüstü dizini diske kaydedilir: panel kapalıyken sandığa taşınan klasörler
# bir sonraki açılışta kimliklerinden tanınıp otomatik bağlanır.
function Load-MonitorState {
    $s=Read-StateFile 'index.json'
    if(!$s){return}
    foreach($k in @($s.known)){if($k -and $k.id -and $k.path){$known[[string]$k.id]=[string]$k.path;$seen[[string]$k.id]=[string]$k.seen}}
    foreach($r in @($s.reviewed)){if($r){$reviewed[[string]$r]=$true}}
}
function Save-MonitorState {
    # 60 gündür masaüstünde görülmeyen kayıtlar silinir. Çakışma bildirilenler kalıcı yazılmaz.
    $limit=(Get-Date).AddDays(-60).ToString('yyyy-MM-dd')
    $items=@()
    foreach($id in @($known.Keys)){
        if($seen[$id] -and $seen[$id] -lt $limit){$known.Remove($id);$seen.Remove($id);continue}
        if($reported.ContainsKey($id)){continue}
        $items+=[pscustomobject]@{id=$id;path=$known[$id];seen=$seen[$id]}
    }
    Write-StateFile 'index.json' @{known=$items;reviewed=@($reviewed.Keys)}
    $script:stateDirty=$false
}
function Index-Desktop {
    $today=(Get-Date).ToString('yyyy-MM-dd')
    foreach($f in Get-PlainFolders $desktop){
        try{$id=[ChestIdentity]::Read($f.FullName)}catch{continue}
        if($known[$id] -ne $f.FullName -or $seen[$id] -ne $today){
            $known[$id]=$f.FullName
            $seen[$id]=$today
            $script:stateDirty=$true
        }
    }
    if($script:stateDirty){try{Save-MonitorState}catch{}}
}
function Sync-Chest {
    # Run on the UI thread: panel operations and observations are serialized.
    # Masaüstünden doğrudan bir grubun içine bırakılan projeler de tanınır.
    foreach($entry in @(Get-ChestProjects)){
        # Okunamayan tek bir klasör (izin, kilit) tüm taramayı durdurmasın.
        try{$key=[ChestIdentity]::Read($entry.FullName)}catch{continue}
        if(!$known.ContainsKey($key)){continue}
        $original=$known[$key]
        if(Is-Bridge $original $entry.FullName){$known.Remove($key);$seen.Remove($key);$script:stateDirty=$true;continue}
        if($entry.Name -ne [IO.Path]::GetFileName($original)){continue}
        try{
            if(Test-Path -LiteralPath $original){throw (T 'err.oldOccupied')}
            New-Bridge $original $entry.FullName
            if(!(Is-Bridge $original $entry.FullName)){throw (T 'err.linkVerify')}
            [IO.File]::SetAttributes($original,([IO.File]::GetAttributes($original) -bor 6))
            $known.Remove($key);$seen.Remove($key);$script:stateDirty=$true
            Set-ProjectRecord $entry.FullName $original
            Notify-User (T 'status.linked' $entry.Name)
        }catch{
            $msg=$_.Exception.Message
            if(!$reported.ContainsKey($key)){
                $reported[$key]=$true
                Note (T 'note.linkFailed' $entry.FullName $original $msg)
            }
        }
    }
    Index-Desktop
}
function Repair-DesktopPath($entry){
    $parent=$entry.Parent.FullName
    $inGroup=((Split-Path $parent -Parent) -eq $dir) -and (Test-Group $parent)
    if(($parent -ne $dir -and !$inGroup) -or (Test-Group $entry.FullName)){throw (T 'err.pickChestProject')}
    Assert-Local $entry.FullName
    $original=Join-Path $desktop $entry.Name
    if(!(Is-Bridge $original $entry.FullName)){
        if(Get-Item -LiteralPath $original -Force -ErrorAction SilentlyContinue){throw (T 'err.oldOccupied2')}
        New-Bridge $original $entry.FullName
        if(!(Is-Bridge $original $entry.FullName)){throw (T 'err.verifyOld')}
    }
    [IO.File]::SetAttributes($original,([IO.File]::GetAttributes($original) -bor 6))
    Set-ProjectRecord $entry.FullName $original
    $hide.Text=(T 'status.verified' $entry.Name)
}
function Get-UnmatchedProjects {
    # Sandıkta olup eski yolu bilinmeyen projeler. Gruplar ve kayıtlı projeler hariç.
    $missing=@()
    $recIds=$null
    foreach($entry in @(Get-ChestProjects)){
        try{$key=[ChestIdentity]::Read($entry.FullName)}catch{continue}
        $old=Join-Path $desktop $entry.Name
        if(Is-Bridge $old $entry.FullName){
            if(([IO.File]::GetAttributes($old) -band 6) -ne 6){Repair-DesktopPath $entry}
            continue
        }
        if($reviewed.ContainsKey($key) -or (Get-Item -LiteralPath $old -Force -ErrorAction SilentlyContinue)){continue}
        if($null -eq $recIds){$recIds=@{};foreach($r in @(Get-ProjectRecords)){if($r.id){$recIds[$r.id]=$true}}}
        if($recIds.ContainsKey($key)){continue}
        $missing+=[pscustomobject]@{Entry=$entry;Key=$key}
    }
    return $missing
}
function Review-Unmatched {
    $found=@(Get-UnmatchedProjects)
    if(!$found.Count){return}
    # Verilen cevap kalıcı: aynı proje her açılışta yeniden sorulmaz.
    foreach($f in $found){$reviewed[$f.Key]=$true}
    try{Save-MonitorState}catch{}
    # Tepsideyken soru gizli pencerenin arkasında kalmasın.
    if(!$form.Visible){Show-Panel}
    $names=($found | ForEach-Object {$_.Entry.Name}) -join "`n"
    if(Ask (T 'unm.text' $names) (T 'unm.title')){foreach($f in $found){Repair-DesktopPath $f.Entry}}
}
function Check-DesktopSupport {
    Assert-Local $desktop
    Assert-Local $dir
    $probe=[IO.Directory]::CreateDirectory((Join-Path $desktop ('EnderChest-Test-'+[guid]::NewGuid())))
    try{
        $id=[ChestIdentity]::Read($probe.FullName)
        Move-Project $probe
        $dest=Join-Path $dir $probe.Name
        if([ChestIdentity]::Read($dest) -ne $id){throw (T 'err.identity')}
    }finally{
        if(Is-Bridge $probe.FullName (Join-Path $dir $probe.Name)){Restore-Project $probe}
        if([IO.Directory]::Exists($probe.FullName) -and !([IO.File]::GetAttributes($probe.FullName) -band [IO.FileAttributes]::ReparsePoint)){[IO.Directory]::Delete($probe.FullName,$false)}
    }
}
