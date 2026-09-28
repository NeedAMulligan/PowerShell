<#
.SYNOPSIS
  Resilient IT - HPE Server Hardware Health Evidence Collector for Windows Server 2008 R2.
.DESCRIPTION
  Read-only evidence collector for ManageEngine Desktop Central/Endpoint Central.
  Designed for Windows Server 2008 R2 and Windows PowerShell 2.0, including execution as SYSTEM.
  Collects WMI inventory, hardware/storage/system event evidence, HPE-related services/drivers,
  and HPE Smart Array CLI evidence when locally available. No remediation or configuration changes.
.NOTES
  Version: 1.3.0
  Compatibility: Windows Server 2008 R2 / Windows PowerShell 2.0+
  Default output: C:\Temp\RIT-ServerHealth-<Computer>-<timestamp> and matching ZIP.
#>
[CmdletBinding()]
param(
    [string]$BaseOutputPath = 'C:\Temp',
    [int]$EventLookbackDays = 365,
    [int]$MaxEventsPerQuery = 10000
)

$ErrorActionPreference = 'Continue'
$ScriptVersion = '1.3.0'
$Computer = $env:COMPUTERNAME
$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$Root = Join-Path $BaseOutputPath (('RIT-ServerHealth-{0}-{1}' -f $Computer,$Stamp))
$EventDir = Join-Path $Root 'EventLogs'
$HpeDir = Join-Path $Root 'HPE'
$RawDir = Join-Path $Root 'Raw'
$LogPath = Join-Path $BaseOutputPath (('RIT-ServerHealth-Collector_{0}_{1}.log' -f $Computer,$Stamp))
$ZipPath = $Root + '.zip'
$Findings = @()
$Collection = @()

function Write-Log {
    param([string]$Message,[string]$Level='INFO')
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Level,$Message
    try { Add-Content -Path $LogPath -Value $line } catch {}
}
function Add-CollectionStatus {
    param([string]$Area,[string]$Status,[string]$Detail)
    $script:Collection += New-Object PSObject -Property @{Area=$Area;Status=$Status;Detail=$Detail}
}
function Add-Finding {
    param([string]$Severity,[string]$Category,[string]$Evidence,[string]$Meaning)
    $script:Findings += New-Object PSObject -Property @{Severity=$Severity;Category=$Category;Evidence=$Evidence;Meaning=$Meaning}
}
function Export-SafeCsv {
    param($InputObject, [string]$Path, [string]$CollectionName = 'Collection')
    try {
        $items = @()
        if ($null -ne $InputObject) {
            foreach ($item in @($InputObject)) {
                if ($null -ne $item) { $items += $item }
            }
        }
        if ($items.Count -gt 0) {
            $items | Export-Csv -Path $Path -NoTypeInformation
        }
        else {
            'Collection,Status,Details' | Out-File -FilePath $Path -Encoding ASCII
            ('"' + ($CollectionName -replace '"','""') + '","NO DATA RETURNED","The query completed but returned no objects. This is a collection result, not proof of healthy hardware."') | Out-File -FilePath $Path -Encoding ASCII -Append
        }
        return $true
    }
    catch {
        try {
            'Collection,Status,Details' | Out-File -FilePath $Path -Encoding ASCII
            ('"' + ($CollectionName -replace '"','""') + '","COLLECTION ERROR","' + (($_.Exception.Message) -replace '"','""') + '"') | Out-File -FilePath $Path -Encoding ASCII -Append
        } catch { }
        return $false
    }
}

function Get-WmiSafe {
    param([string]$ClassName,[string]$Namespace='root\cimv2')
    try { return @(Get-WmiObject -Namespace $Namespace -Class $ClassName -ErrorAction Stop) }
    catch { Write-Log (('WMI query failed: {0}/{1} :: {2}' -f $Namespace,$ClassName,$_.Exception.Message)) 'WARN'; return @() }
}
function Convert-WmiDate {
    param($Value)
    if(-not $Value){ return $null }
    try { return [Management.ManagementDateTimeConverter]::ToDateTime([string]$Value) } catch { return $Value }
}
function Get-EventsSafe {
    param([hashtable]$Filter,[string]$Name)
    try {
        $ev = @(Get-WinEvent -FilterHashtable $Filter -MaxEvents $MaxEventsPerQuery -ErrorAction Stop)
        Add-CollectionStatus $Name 'Collected' (('{0} event(s)' -f $ev.Count))
        return $ev
    } catch {
        $msg = $_.Exception.Message
        if($msg -match 'No events were found|No events were found that match'){ Add-CollectionStatus $Name 'Collected' '0 events'; return @() }
        Add-CollectionStatus $Name 'Unavailable' $msg
        Write-Log (('{0} event query unavailable: {1}' -f $Name,$msg)) 'WARN'
        return @()
    }
}
function Convert-EventRows {
    param($Events)
    $rows = @()
    foreach($e in @($Events)){
        $rows += New-Object PSObject -Property @{TimeCreated=$e.TimeCreated;Id=$e.Id;LevelDisplayName=$e.LevelDisplayName;ProviderName=$e.ProviderName;MachineName=$e.MachineName;RecordId=$e.RecordId;Message=$e.Message}
    }
    return $rows
}
function Invoke-CaptureCommand {
    param([string]$Exe,[string[]]$Arguments,[string]$OutputFile)
    try {
        $cmd = Get-Command $Exe -ErrorAction Stop
        $text = & $cmd.Path @Arguments 2>&1 | Out-String -Width 4096
        Set-Content -Path $OutputFile -Value $text
        return $true
    } catch {
        Set-Content -Path $OutputFile -Value (('Unavailable: {0}' -f $_.Exception.Message))
        return $false
    }
}
function Test-IdInList {
    param([int]$Id,[int[]]$List)
    return ($List -contains $Id)
}
function New-ZipFilePS2 {
    param([string]$SourceFolder,[string]$DestinationZip)
    try {
        if(Test-Path $DestinationZip){ Remove-Item $DestinationZip -Force }
        Set-Content -Path $DestinationZip -Value ('PK' + [char]5 + [char]6 + ([char]0 * 18)) -Encoding Byte -ErrorAction Stop
    } catch {
        # Set-Content -Encoding Byte cannot write strings consistently on all PS2 builds; use FileStream fallback.
        try {
            $bytes = [byte[]](80,75,5,6,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
            [System.IO.File]::WriteAllBytes($DestinationZip,$bytes)
        } catch { return $false }
    }
    try {
        $shell = New-Object -ComObject Shell.Application
        $zip = $shell.NameSpace($DestinationZip)
        $source = $shell.NameSpace($SourceFolder)
        if(($zip -eq $null) -or ($source -eq $null)){ return $false }
        $zip.CopyHere($source.Items(),16)
        $expected = @(Get-ChildItem -Path $SourceFolder -Recurse | Where-Object {-not $_.PSIsContainer}).Count
        $deadline = (Get-Date).AddMinutes(10)
        do {
            Start-Sleep -Seconds 2
            $current = @($zip.Items()).Count
        } while(($current -lt 1) -and ((Get-Date) -lt $deadline))
        Start-Sleep -Seconds 3
        return (Test-Path $DestinationZip)
    } catch { Write-Log (('ZIP creation exception: {0}' -f $_.Exception.Message)) 'WARN'; return $false }
}

if($EventLookbackDays -lt 1){$EventLookbackDays=365}
if($MaxEventsPerQuery -lt 100){$MaxEventsPerQuery=10000}
try {
    if(-not (Test-Path $BaseOutputPath)){ New-Item -ItemType Directory -Path $BaseOutputPath -Force | Out-Null }
    New-Item -ItemType Directory -Path $Root -Force | Out-Null
    New-Item -ItemType Directory -Path $EventDir -Force | Out-Null
    New-Item -ItemType Directory -Path $HpeDir -Force | Out-Null
    New-Item -ItemType Directory -Path $RawDir -Force | Out-Null
} catch { try { Add-Content -Path $LogPath -Value (('Unable to initialize output: {0}' -f $_.Exception.Message)) } catch { }; exit 2 }

Write-Log (('Starting Resilient IT HPE Server Hardware Health Evidence Collector v{0} on {1}.' -f $ScriptVersion,$Computer))
try {$runAs=[Security.Principal.WindowsIdentity]::GetCurrent().Name}catch{$runAs='Unknown'}
$procBits = if([IntPtr]::Size -eq 8){'64-bit'}else{'32-bit'}
Write-Log (('Running as {0}; process architecture: {1}; PowerShell: {2}' -f $runAs,$procBits,$PSVersionTable.PSVersion.ToString()))
Write-Log (('Event lookback: {0} days. Output: {1}' -f $EventLookbackDays,$Root))
$StartTime = (Get-Date).AddDays(-$EventLookbackDays)

# Core WMI inventory
$cs=@();$os=@();$bios=@();$bb=@();$cpu=@();$mem=@();$disk=@();$vol=@();$scsi=@();$pnp=@();$net=@()
try {
    $cs = Get-WmiSafe 'Win32_ComputerSystem'
    $os = Get-WmiSafe 'Win32_OperatingSystem'
    $bios = Get-WmiSafe 'Win32_BIOS'
    $bb = Get-WmiSafe 'Win32_BaseBoard'
    $cpu = Get-WmiSafe 'Win32_Processor'
    $mem = Get-WmiSafe 'Win32_PhysicalMemory'
    $disk = Get-WmiSafe 'Win32_DiskDrive'
    $vol = Get-WmiSafe 'Win32_LogicalDisk'
    $scsi = Get-WmiSafe 'Win32_SCSIController'
    $pnp = Get-WmiSafe 'Win32_PnPEntity'
    $net = @(Get-WmiSafe 'Win32_NetworkAdapterConfiguration' | Where-Object {$_.IPEnabled -eq $true})
    $cs1=$cs | Select-Object -First 1; $os1=$os | Select-Object -First 1; $bios1=$bios | Select-Object -First 1; $bb1=$bb | Select-Object -First 1
    $boot=Convert-WmiDate $os1.LastBootUpTime
    $installDate=Convert-WmiDate $os1.InstallDate
    $biosDate=Convert-WmiDate $bios1.ReleaseDate
    $uptimeDays=$null
    if($boot -is [datetime]){$uptimeDays=[math]::Round(((Get-Date)-$boot).TotalDays,2)}
    $inventory = New-Object PSObject -Property @{
        ComputerName=$Computer;Manufacturer=$cs1.Manufacturer;Model=$cs1.Model;SystemType=$cs1.SystemType;SerialNumber=$bios1.SerialNumber;
        BIOSManufacturer=$bios1.Manufacturer;BIOSVersion=($bios1.SMBIOSBIOSVersion -join '; ');BIOSReleaseDate=$biosDate;BaseBoardProduct=$bb1.Product;
        OS=$os1.Caption;OSVersion=$os1.Version;OSBuild=$os1.BuildNumber;OSInstallDate=$installDate;ServicePackMajor=$os1.ServicePackMajorVersion;
        LastBoot=$boot;UptimeDays=$uptimeDays;TotalPhysicalMemoryGB=[math]::Round(($cs1.TotalPhysicalMemory/1GB),2);
        ProcessorCount=@($cpu).Count;MemoryModuleCount=@($mem).Count;PowerShellVersion=$PSVersionTable.PSVersion.ToString();CollectionTime=Get-Date
    }
    Export-SafeCsv $inventory (Join-Path $Root '01-System-Inventory.csv') | Out-Null
    Export-SafeCsv $bios (Join-Path $Root '02-BIOS-Firmware.csv') | Out-Null
    Export-SafeCsv $cpu (Join-Path $Root '03-Processor.csv') | Out-Null
    Export-SafeCsv $mem (Join-Path $Root '04-Memory.csv') | Out-Null
    Export-SafeCsv $disk (Join-Path $Root '05-Physical-Disks.csv') | Out-Null
    Export-SafeCsv $vol (Join-Path $Root '06-Volumes.csv') | Out-Null
    Export-SafeCsv $scsi (Join-Path $Root '07-Storage-Controllers.csv') | Out-Null
    Export-SafeCsv $net (Join-Path $Root '08-Network-Adapters.csv') | Out-Null
    Export-SafeCsv $pnp (Join-Path $RawDir 'PNP-Devices.csv') | Out-Null
    Add-CollectionStatus 'Core hardware inventory' 'Collected' 'Classic WMI inventory exported.'
    if($cs1.Manufacturer -notmatch 'HPE|Hewlett|HP'){ Add-Finding 'INFORMATIONAL' 'Platform' (('Manufacturer reported as {0}' -f $cs1.Manufacturer)) 'System did not identify itself as HP/HPE through Win32_ComputerSystem.' }
    if(($biosDate -is [datetime]) -and ($biosDate -lt (Get-Date).AddYears(-5))){ Add-Finding 'INFORMATIONAL' 'Lifecycle' (('BIOS release date: {0}' -f $biosDate)) 'Firmware/platform age is a lifecycle and support-risk indicator, but age alone does not prove imminent failure.' }
    if($os1.Caption -match '2008 R2'){
        Add-Finding 'WARNING' 'Lifecycle/Operating System' (('Operating system: {0}, build {1}, Service Pack {2}' -f $os1.Caption,$os1.BuildNumber,$os1.ServicePackMajorVersion)) 'Windows Server 2008 R2 is a legacy operating system. Treat this as lifecycle/security/support evidence separately from physical hardware-failure evidence.'
    }
} catch { Write-Log (('Core inventory failure: {0}' -f $_.Exception.Message)) 'FAIL'; Add-CollectionStatus 'Core hardware inventory' 'Failed' $_.Exception.Message }

# Native system evidence
Invoke-CaptureCommand 'systeminfo.exe' @() (Join-Path $RawDir 'SystemInfo.txt') | Out-Null
Invoke-CaptureCommand 'driverquery.exe' @('/v') (Join-Path $RawDir 'DriverQuery.txt') | Out-Null
Invoke-CaptureCommand 'wmic.exe' @('diskdrive','get','Model,Name,InterfaceType,MediaType,SerialNumber,Size,Status','/format:list') (Join-Path $RawDir 'WMIC-DiskDrive.txt') | Out-Null
Invoke-CaptureCommand 'wmic.exe' @('memorychip','get','BankLabel,Capacity,DeviceLocator,Manufacturer,PartNumber,SerialNumber,Speed','/format:list') (Join-Path $RawDir 'WMIC-Memory.txt') | Out-Null
try { Get-HotFix | Sort-Object InstalledOn -Descending | Export-Csv (Join-Path $RawDir 'Installed-Hotfixes.csv') -NoTypeInformation } catch {}

# Events: WHEA
$whea = Get-EventsSafe @{LogName='System';StartTime=$StartTime;ProviderName='Microsoft-Windows-WHEA-Logger'} 'WHEA hardware events'
Export-SafeCsv (Convert-EventRows $whea) (Join-Path $EventDir 'WHEA-Hardware-Errors.csv') | Out-Null
$wheaCount = 0; foreach($x in $whea){ if($null -ne $x){$wheaCount++} }
if($wheaCount -gt 0){ Add-Finding 'WARNING' 'Hardware/WHEA' (('{0} WHEA event(s) found in the last {1} days.' -f $wheaCount,$EventLookbackDays)) 'WHEA records hardware-reported errors. Event details and recurrence must be reviewed to distinguish corrected from uncorrected faults.' }

# Broad System warning/error collection, then storage filter. Avoid FilterHashtable Level arrays for old event engines.
$sysErr = Get-EventsSafe @{LogName='System';StartTime=$StartTime} 'System events for storage filtering'
$storage = @()
foreach($e in @($sysErr)){
    $provider=[string]$e.ProviderName
    if(($provider -match 'disk|stor|ntfs|vol|array|ciss|cpq|hp') -and (($e.Level -eq 1) -or ($e.Level -eq 2) -or ($e.Level -eq 3))){$storage += $e}
}
Export-SafeCsv (Convert-EventRows $storage) (Join-Path $EventDir 'Disk-Storage-Errors.csv') | Out-Null
$criticalStorageIds = @(7,9,11,15,51,55,57,98,129,153,157)
$storageKey=@()
foreach($e in @($storage)){if(Test-IdInList ([int]$e.Id) $criticalStorageIds){$storageKey += $e}}
if(@($storageKey).Count -gt 0){ Add-Finding 'WARNING' 'Storage' (('{0} notable disk/storage/filesystem event(s) found (IDs 7,9,11,15,51,55,57,98,129,153,157).' -f @($storageKey).Count)) 'These events can indicate controller/device errors, timeouts, resets, retries, filesystem problems, or device removal. Correlate frequency and messages with Smart Array and iLO IML.' }

$unexpected = Get-EventsSafe @{LogName='System';StartTime=$StartTime;Id=41,6008,1074,6005,6006} 'Shutdown/restart events'
Export-SafeCsv (Convert-EventRows $unexpected) (Join-Path $EventDir 'Shutdown-Restart-Events.csv') | Out-Null
$badShutdown=@();foreach($e in @($unexpected)){if(($e.Id -eq 41) -or ($e.Id -eq 6008)){$badShutdown += $e}}
if(@($badShutdown).Count -gt 0){ Add-Finding 'WARNING' 'Stability' (('{0} unexpected shutdown/Kernel-Power event(s) found.' -f @($badShutdown).Count)) 'Unexpected shutdowns can result from power, hardware, OS, or administrative causes and should be correlated with surrounding events and iLO IML.' }

$bug = Get-EventsSafe @{LogName='System';StartTime=$StartTime;Id=1001} 'System Event ID 1001 / bugcheck candidates'
Export-SafeCsv (Convert-EventRows $bug) (Join-Path $EventDir 'BugCheck-Candidates.csv') | Out-Null
$bugCount = 0; foreach($x in $bug){ if($null -ne $x){$bugCount++} }
if($bugCount -gt 0){ Add-Finding 'WARNING' 'Stability' (('{0} Event ID 1001 system-error/bugcheck candidate(s) found.' -f $bugCount)) 'Review provider and message details. Event ID 1001 alone does not establish hardware as the cause.' }

$critical=@();foreach($e in @($sysErr)){if($e.Level -eq 1){$critical += $e}}
Export-SafeCsv (Convert-EventRows $critical) (Join-Path $EventDir 'Critical-System-Events.csv') | Out-Null
Add-CollectionStatus 'Critical System events' 'Collected' (('{0} critical event(s)' -f @($critical).Count))

# Save notable event-ID subset for easy review
$notableIds=@(7,9,11,15,18,19,20,41,47,51,55,57,98,129,153,157,6008)
$notable=@();foreach($e in @($sysErr)){if(Test-IdInList ([int]$e.Id) $notableIds){$notable += $e}}
Export-SafeCsv (Convert-EventRows $notable) (Join-Path $EventDir 'Notable-Hardware-Storage-Power-Events.csv') | Out-Null

# Installed HP/HPE software from registry only; never Win32_Product.
try {
    $apps=@()
    $paths=@('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')
    foreach($key in $paths){
        $items=Get-ItemProperty $key -ErrorAction SilentlyContinue
        foreach($item in @($items)){
            if(([string]$item.DisplayName) -match 'HPE|Hewlett|HP |Smart Storage|Array|iLO|ProLiant'){
                $apps += New-Object PSObject -Property @{DisplayName=$item.DisplayName;DisplayVersion=$item.DisplayVersion;Publisher=$item.Publisher;InstallDate=$item.InstallDate}
            }
        }
    }
    Export-SafeCsv $apps (Join-Path $RawDir 'Installed-HPE-Software.csv') | Out-Null
} catch { Write-Log (('HPE installed-software registry collection failed: {0}' -f $_.Exception.Message)) 'WARN' }

# HPE services/drivers via classic WMI.
try {
    $services=@(Get-WmiSafe 'Win32_Service' | Where-Object {$_.Name -match 'hp|hpe|ilo|array|stor|ciss|cpq' -or $_.DisplayName -match 'HPE|Hewlett|HP |iLO|Smart Array|ProLiant'})
    $drivers=@(Get-WmiSafe 'Win32_SystemDriver' | Where-Object {$_.Name -match 'hp|hpe|ciss|stor|cpq' -or $_.DisplayName -match 'HPE|Hewlett|HP |Smart Array|ProLiant'})
    Export-SafeCsv ($services | Select-Object Name,DisplayName,State,StartMode,PathName) (Join-Path $HpeDir 'HPE-Related-Services.csv') | Out-Null
    Export-SafeCsv ($drivers | Select-Object Name,DisplayName,State,StartMode,PathName) (Join-Path $HpeDir 'HPE-Storage-Related-Drivers.csv') | Out-Null
    Add-CollectionStatus 'HPE services/drivers' 'Collected' (('{0} service(s), {1} driver(s)' -f $services.Count,$drivers.Count))
} catch { Add-CollectionStatus 'HPE services/drivers' 'Unavailable' $_.Exception.Message }

# Deep legacy HP/HPE WMI/WBEM discovery. Gen8 support packs commonly expose data outside root\cimv2.
try {
    $namespaceRows=@()
    $rootNs=@(Get-WmiObject -Namespace root -Class __Namespace -ErrorAction Stop)
    foreach($n in $rootNs){
        $namespaceRows += New-Object PSObject -Property @{Namespace=('root\'+$n.Name);Source='root'}
        if(([string]$n.Name) -match 'hp|hpe|compaq'){
            try {
                $children=@(Get-WmiObject -Namespace ('root\'+$n.Name) -Class __Namespace -ErrorAction SilentlyContinue)
                foreach($c in $children){$namespaceRows += New-Object PSObject -Property @{Namespace=('root\'+$n.Name+'\'+$c.Name);Source='child'}}
            } catch {}
        }
    }
    Export-SafeCsv $namespaceRows (Join-Path $HpeDir 'HPE-WMI-Namespaces.csv') 'HPE WMI namespaces' | Out-Null
    $hpNs=@($namespaceRows | Where-Object {$_.Namespace -match 'hp|hpe|compaq'})
    Add-CollectionStatus 'HPE WMI providers' 'Collected' (('{0} HP/HPE/Compaq namespace candidate(s)' -f $hpNs.Count))
    foreach($nr in $hpNs){
        $nsName=[string]$nr.Namespace
        $safeNs=$nsName -replace '[\\/:*?"<>|]','_'
        try {
            $classes=@(Get-WmiObject -Namespace $nsName -Class __Class -ErrorAction Stop | Where-Object {$_.__CLASS -notmatch '^__'} | Select-Object -ExpandProperty __CLASS)
            Set-Content -Path (Join-Path $HpeDir ('WMI-Classes-'+$safeNs+'.txt')) -Value $classes
            foreach($className in $classes){
                if(([string]$className) -match 'Array|Storage|Drive|Disk|Controller|Battery|Cache|Memory|Fan|Power|Temperature|Thermal|Health|System|Enclosure|Chassis|Processor|Event|Log|iLO'){
                    try {
                        $objs=@(Get-WmiObject -Namespace $nsName -Class $className -ErrorAction Stop)
                        if($objs.Count -gt 0){
                            $safeClass=([string]$className) -replace '[\\/:*?"<>|]','_'
                            $objs | Format-List * | Out-File (Join-Path $HpeDir ('WMI-'+$safeNs+'-'+$safeClass+'.txt')) -Width 4096
                        }
                    } catch {}
                }
            }
        } catch {}
    }
} catch {Add-CollectionStatus 'HPE WMI providers' 'Unavailable' $_.Exception.Message}

# Locate legacy and current Smart Array utilities. Search known paths first, then HP/HPE program trees.
$hpeCandidates = @(
'C:\Program Files\Smart Storage Administrator\ssacli\bin\ssacli.exe',
'C:\Program Files\Smart Storage Administrator\ssacli\bin\hpssacli.exe',
'C:\Program Files\HP\hpssacli\bin\hpssacli.exe',
'C:\Program Files\Compaq\Hpacucli\Bin\hpacucli.exe',
'C:\Program Files\Hewlett-Packard\Array Configuration Utility\Bin\hpacucli.exe',
'C:\Program Files\HP\Array Configuration Utility\Bin\hpacucli.exe',
'C:\Program Files (x86)\Compaq\Hpacucli\Bin\hpacucli.exe',
'C:\Program Files (x86)\Hewlett-Packard\Array Configuration Utility\Bin\hpacucli.exe',
'C:\Program Files (x86)\HP\Array Configuration Utility\Bin\hpacucli.exe'
)
$searchRoots=@('C:\Program Files\HP','C:\Program Files (x86)\HP','C:\Program Files\Hewlett-Packard','C:\Program Files (x86)\Hewlett-Packard','C:\Program Files\Compaq','C:\Program Files (x86)\Compaq')
$foundTools=@()
foreach($candidate in $hpeCandidates){if(Test-Path $candidate){$foundTools += $candidate}}
foreach($sr in $searchRoots){
    if(Test-Path $sr){
        try {
            $hits=@(Get-ChildItem -Path $sr -Recurse -ErrorAction SilentlyContinue | Where-Object {-not $_.PSIsContainer -and ($_.Name -match '^(hpacucli|hpssacli|ssacli|hponcfg|cpqacuxe)\.exe$')})
            foreach($hit in $hits){if($foundTools -notcontains $hit.FullName){$foundTools += $hit.FullName}}
        } catch {}
    }
}
Set-Content -Path (Join-Path $HpeDir 'HPE-Management-Executables-Detected.txt') -Value $foundTools
$ssa=$null
foreach($tool in $foundTools){if(($ssa -eq $null) -and ((Split-Path $tool -Leaf) -match '^(hpacucli|hpssacli|ssacli)\.exe$')){$ssa=$tool}}
$hponcfg=$null
foreach($tool in $foundTools){if(($hponcfg -eq $null) -and ((Split-Path $tool -Leaf) -match '^hponcfg\.exe$')){$hponcfg=$tool}}
$hpeInfo=@('Computer: '+$Computer)
if($cs.Count -gt 0){$hpeInfo += ('Manufacturer/Model: '+$cs[0].Manufacturer+' '+$cs[0].Model)}
if($bios.Count -gt 0){$hpeInfo += ('Serial: '+$bios[0].SerialNumber)}
if($ssa -ne $null){
    $hpeInfo += ('Smart Array CLI detected: '+$ssa)
    try {
        $commands=@(
            @{Name='SmartArray-Controller-Status.txt';Args=@('ctrl','all','show','status')},
            @{Name='SmartArray-Controller-Detail.txt';Args=@('ctrl','all','show','detail')},
            @{Name='SmartArray-Configuration.txt';Args=@('ctrl','all','show','config')},
            @{Name='SmartArray-Configuration-Detail.txt';Args=@('ctrl','all','show','config','detail')},
            @{Name='SmartArray-PhysicalDrives-Detail.txt';Args=@('ctrl','all','pd','all','show','detail')},
            @{Name='SmartArray-LogicalDrives-Detail.txt';Args=@('ctrl','all','ld','all','show','detail')}
        )
        foreach($c in $commands){
            $outFile=Join-Path $HpeDir $c.Name
            try { & $ssa $c.Args 2>&1 | Out-File $outFile -Width 4096 } catch { Set-Content $outFile ('Command failed: '+$_.Exception.Message) }
        }
        Add-CollectionStatus 'HPE Smart Array CLI' 'Collected' $ssa
        $allSmart=''
        foreach($c in $commands){$f=Join-Path $HpeDir $c.Name;if(Test-Path $f){$allSmart += [string]::Join("`n",@(Get-Content $f -ErrorAction SilentlyContinue))}}
        if($allSmart -match '(?im)\b(Failed|Degraded|Predictive Failure|Interim Recovery Mode|Recovering|Rebuilding)\b'){
            Add-Finding 'CRITICAL' 'HPE Smart Array' 'Smart Array output contains a failed/degraded/predictive/recovery state.' 'This is direct controller-level evidence requiring immediate review and protection of critical data.'
        }
        if($allSmart -match '(?im)(Cache Status|Battery/Capacitor Status|Cache Backup Power Source).*?(Failed|Degraded|Replace|Low|Not Present|Disabled)'){
            Add-Finding 'CRITICAL' 'HPE Smart Array Cache' 'Smart Array output indicates a cache backup/battery/capacitor problem.' 'Loss or degradation of controller cache protection materially increases storage risk and should be addressed immediately.'
        }
    } catch {Add-CollectionStatus 'HPE Smart Array CLI' 'Failed' $_.Exception.Message}
} else {
    $hpeInfo += 'Smart Array CLI: not detected locally after recursive HP/HPE program-directory search.'
    Add-CollectionStatus 'HPE Smart Array CLI' 'Unavailable' 'No hpacucli/hpssacli/ssacli executable found.'
}
if($hponcfg -ne $null){
    $hpeInfo += ('HPONCFG detected: '+$hponcfg)
    try {
        & $hponcfg '/w' (Join-Path $HpeDir 'iLO-Configuration.xml') 2>&1 | Out-File (Join-Path $HpeDir 'HPONCFG-Output.txt') -Width 4096
        Add-CollectionStatus 'HPONCFG/iLO local interface' 'Collected' $hponcfg
    } catch {Add-CollectionStatus 'HPONCFG/iLO local interface' 'Failed' $_.Exception.Message}
} else {Add-CollectionStatus 'HPONCFG/iLO local interface' 'Unavailable' 'hponcfg.exe not found.'}
Set-Content -Path (Join-Path $HpeDir 'HPE-Software-and-Interfaces-Detected.txt') -Value $hpeInfo

# Discover HP/HPE event logs with wevtutil (more compatible than Get-WinEvent -ListLog on old hosts).
try {
    $allLogs=@(& wevtutil.exe el 2>$null)
    $hpeLogs=@($allLogs | Where-Object {$_ -match 'HP|HPE|iLO|Smart|ProLiant'})
    Set-Content -Path (Join-Path $HpeDir 'HPE-EventLogs-Detected.txt') -Value $hpeLogs
    foreach($log in $hpeLogs){
        $safe=([string]$log) -replace '[\\/:*?"<>|]','_'
        try {
            & wevtutil.exe qe ([string]$log) '/f:text' '/rd:true' ('/c:{0}' -f $MaxEventsPerQuery) 2>&1 | Out-File (Join-Path $HpeDir (('EventLog-{0}.txt' -f $safe))) -Width 4096
        } catch {}
    }
    Add-CollectionStatus 'HPE event logs' 'Collected' (('{0} HPE/HP-named log(s) detected' -f $hpeLogs.Count))
} catch {Add-CollectionStatus 'HPE event logs' 'Unavailable' $_.Exception.Message}

# Executive summary
Export-SafeCsv $Findings (Join-Path $Root 'Findings.csv') | Out-Null
Export-SafeCsv $Collection (Join-Path $Root 'Collection-Status.csv') | Out-Null
$critCount=@($Findings | Where-Object {$_.Severity -eq 'CRITICAL'}).Count
$warnCount=@($Findings | Where-Object {$_.Severity -eq 'WARNING'}).Count
$infoCount=@($Findings | Where-Object {$_.Severity -eq 'INFORMATIONAL'}).Count
$summary=@()
$summary += 'RESILIENT IT - HPE SERVER HARDWARE HEALTH EVIDENCE SUMMARY'
$summary += ('='*72)
$summary += ('Computer: '+$Computer)
if($cs.Count -gt 0){$summary += ('Platform: '+$cs[0].Manufacturer+' '+$cs[0].Model)}
if($bios.Count -gt 0){$summary += ('Serial Number: '+$bios[0].SerialNumber)}
if($os.Count -gt 0){$summary += ('Operating System: '+$os[0].Caption+' '+$os[0].Version+' Build '+$os[0].BuildNumber)}
$summary += ('PowerShell: '+$PSVersionTable.PSVersion.ToString())
$summary += ('Collected: '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$summary += ('Lookback: '+$EventLookbackDays+' days')
$summary += ('Collector version: '+$ScriptVersion)
$summary += ''
$summary += (('Finding counts: CRITICAL={0}  WARNING={1}  INFORMATIONAL={2}' -f $critCount,$warnCount,$infoCount))
$summary += ''
$summary += 'IMPORTANT: Findings are evidence indicators, not an automatic diagnosis. Correlate Windows evidence with the HPE iLO Integrated Management Log (IML), Active Health System (AHS), and Smart Array status before making a hardware-failure determination.'
$summary += ''
$summary += 'FINDINGS'
$summary += ('-'*72)
if($Findings.Count -eq 0){$summary += 'No automatically classified findings were detected. This does NOT establish that the hardware is healthy. Review Collection-Status.csv and obtain iLO IML/AHS evidence.'}
foreach($f in $Findings){$summary += (('[{0}] {1}: {2}' -f $f.Severity,$f.Category,$f.Evidence));$summary += ('  Interpretation: '+$f.Meaning)}
$summary += ''
$summary += 'COLLECTION COVERAGE'
$summary += ('-'*72)
foreach($c in $Collection){$summary += (('[{0}] {1}: {2}' -f $c.Status,$c.Area,$c.Detail))}
Set-Content -Path (Join-Path $Root '00-Executive-Summary.txt') -Value $summary

# SHA-256 manifest using certutil, available on Server 2008 R2, instead of Get-FileHash.
try {
    $manifest=Join-Path $Root 'Evidence-SHA256-Manifest.txt'
    'SHA-256 evidence manifest' | Out-File $manifest
    foreach($file in @(Get-ChildItem -Path $Root -Recurse | Where-Object {-not $_.PSIsContainer -and $_.FullName -ne $manifest})){
        ('FILE: '+$file.FullName) | Out-File $manifest -Append
        & certutil.exe -hashfile $file.FullName SHA256 2>&1 | Out-File $manifest -Append
        '' | Out-File $manifest -Append
    }
    Add-CollectionStatus 'Evidence hash manifest' 'Collected' 'SHA-256 generated with certutil.'
} catch {Write-Log (('Hash manifest failed: {0}' -f $_.Exception.Message)) 'WARN'}

# Re-export collection status after manifest status.
Export-SafeCsv $Collection (Join-Path $Root 'Collection-Status.csv') | Out-Null

$zipOk=New-ZipFilePS2 $Root $ZipPath
if($zipOk){Write-Log (('Evidence ZIP created: {0}' -f $ZipPath)) 'PASS'}else{Write-Log 'ZIP creation failed. Evidence folder remains intact and can be collected directly.' 'WARN'}
Write-Log (('Collection complete. CRITICAL={0} WARNING={1} INFORMATIONAL={2}' -f $critCount,$warnCount,$infoCount)) 'PASS'
Write-Log ('OUTPUT_FOLDER='+$Root)
if(Test-Path $ZipPath){Write-Log ('OUTPUT_ZIP='+$ZipPath)}
exit 0
