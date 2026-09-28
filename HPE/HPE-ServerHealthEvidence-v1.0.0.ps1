#requires -version 5.1
<#
.SYNOPSIS
  Resilient IT - HPE/Windows Server Hardware Health Evidence Collector.
.DESCRIPTION
  Read-only evidence collector intended for execution by ManageEngine Endpoint Central/Desktop Central as SYSTEM.
  Collects hardware inventory, Windows hardware/storage/system events, reliability indicators, storage status,
  and opportunistic HPE/iLO/Smart Array information when locally available. No remediation or configuration changes.
.NOTES
  Version: 1.0.0
  Default output: C:\Temp\RIT-ServerHealth-<Computer>-<timestamp> and matching ZIP.
  Recommended execution context: NT AUTHORITY\SYSTEM, 64-bit Windows PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [string]$BaseOutputPath = 'C:\Temp',
    [ValidateRange(1,3650)][int]$EventLookbackDays = 365,
    [ValidateRange(100,100000)][int]$MaxEventsPerQuery = 10000
)

$ErrorActionPreference = 'Stop'
$ScriptVersion = '1.0.0'
$Computer = $env:COMPUTERNAME
$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$Root = Join-Path $BaseOutputPath ("RIT-ServerHealth-{0}-{1}" -f $Computer,$Stamp)
$EventDir = Join-Path $Root 'EventLogs'
$HpeDir = Join-Path $Root 'HPE'
$RawDir = Join-Path $Root 'Raw'
$LogPath = Join-Path $BaseOutputPath ("RIT-ServerHealth-Collector_{0}_{1}.log" -f $Computer,$Stamp)
$ZipPath = "$Root.zip"
$Findings = New-Object System.Collections.Generic.List[object]
$Collection = New-Object System.Collections.Generic.List[object]

function Write-Log {
    param([string]$Message,[ValidateSet('INFO','PASS','WARN','FAIL')][string]$Level='INFO')
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Level,$Message
    Write-Output $line
    try { Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8 } catch {}
}
function Add-CollectionStatus {
    param([string]$Area,[string]$Status,[string]$Detail)
    $Collection.Add([pscustomobject]@{Area=$Area;Status=$Status;Detail=$Detail}) | Out-Null
}
function Add-Finding {
    param([ValidateSet('CRITICAL','WARNING','INFORMATIONAL')][string]$Severity,[string]$Category,[string]$Evidence,[string]$Meaning)
    $Findings.Add([pscustomobject]@{Severity=$Severity;Category=$Category;Evidence=$Evidence;Meaning=$Meaning}) | Out-Null
}
function Export-SafeCsv {
    param($InputObject,[string]$Path)
    try {
        @($InputObject) | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8
        return $true
    } catch { Write-Log "CSV export failed: $Path :: $($_.Exception.Message)" WARN; return $false }
}
function Get-CimSafe {
    param([string]$ClassName,[string]$Namespace='root/cimv2')
    try { @(Get-CimInstance -Namespace $Namespace -ClassName $ClassName -ErrorAction Stop) }
    catch { Write-Log "CIM query failed: $Namespace/$ClassName :: $($_.Exception.Message)" WARN; @() }
}
function Get-EventsSafe {
    param([hashtable]$Filter,[string]$Name)
    try {
        $ev = @(Get-WinEvent -FilterHashtable $Filter -MaxEvents $MaxEventsPerQuery -ErrorAction Stop)
        Add-CollectionStatus $Name 'Collected' ("{0} event(s)" -f $ev.Count)
        return $ev
    } catch {
        if ($_.Exception.Message -match 'No events were found') { Add-CollectionStatus $Name 'Collected' '0 events'; return @() }
        Add-CollectionStatus $Name 'Unavailable' $_.Exception.Message
        Write-Log "$Name event query unavailable: $($_.Exception.Message)" WARN
        return @()
    }
}
function Convert-EventRows {
    param($Events)
    @($Events | ForEach-Object {
        [pscustomobject]@{TimeCreated=$_.TimeCreated;Id=$_.Id;LevelDisplayName=$_.LevelDisplayName;ProviderName=$_.ProviderName;MachineName=$_.MachineName;RecordId=$_.RecordId;Message=$_.Message}
    })
}
function Invoke-CaptureCommand {
    param([string]$Exe,[string[]]$Arguments,[string]$OutputFile)
    try {
        $cmd = Get-Command $Exe -ErrorAction Stop
        $text = & $cmd.Source @Arguments 2>&1 | Out-String -Width 4096
        Set-Content -LiteralPath $OutputFile -Value $text -Encoding UTF8
        return $true
    } catch {
        Set-Content -LiteralPath $OutputFile -Value ("Unavailable: {0}" -f $_.Exception.Message) -Encoding UTF8
        return $false
    }
}

try {
    New-Item -ItemType Directory -Path $BaseOutputPath -Force | Out-Null
    New-Item -ItemType Directory -Path $Root,$EventDir,$HpeDir,$RawDir -Force | Out-Null
    Start-Transcript -Path (Join-Path $Root 'Collector-Transcript.txt') -Force | Out-Null
} catch { Write-Output "Unable to initialize output: $($_.Exception.Message)"; exit 2 }

Write-Log "Starting Resilient IT Server Hardware Health Evidence Collector v$ScriptVersion on $Computer."
Write-Log "Running as $([Security.Principal.WindowsIdentity]::GetCurrent().Name); 64-bit process: $([Environment]::Is64BitProcess)."
Write-Log "Event lookback: $EventLookbackDays days. Output: $Root"
$StartTime = (Get-Date).AddDays(-$EventLookbackDays)

# Core inventory
try {
    $cs = Get-CimSafe Win32_ComputerSystem
    $os = Get-CimSafe Win32_OperatingSystem
    $bios = Get-CimSafe Win32_BIOS
    $bb = Get-CimSafe Win32_BaseBoard
    $cpu = Get-CimSafe Win32_Processor
    $mem = Get-CimSafe Win32_PhysicalMemory
    $disk = Get-CimSafe Win32_DiskDrive
    $vol = Get-CimSafe Win32_LogicalDisk
    $scsi = Get-CimSafe Win32_SCSIController
    $pnp = Get-CimSafe Win32_PnPEntity
    $net = Get-CimSafe Win32_NetworkAdapterConfiguration | Where-Object {$_.IPEnabled}

    $boot = if($os.LastBootUpTime){[datetime]$os.LastBootUpTime}else{$null}
    $uptimeDays = if($boot){[math]::Round(((Get-Date)-$boot).TotalDays,2)}else{$null}
    $inventory = [pscustomobject]@{
        ComputerName=$Computer; Manufacturer=$cs.Manufacturer; Model=$cs.Model; SystemType=$cs.SystemType;
        SerialNumber=$bios.SerialNumber; BIOSManufacturer=$bios.Manufacturer; BIOSVersion=($bios.SMBIOSBIOSVersion -join '; ');
        BIOSReleaseDate=$bios.ReleaseDate; BaseBoardProduct=$bb.Product; OS=$os.Caption; OSVersion=$os.Version; OSBuild=$os.BuildNumber;
        LastBoot=$boot; UptimeDays=$uptimeDays; TotalPhysicalMemoryGB=[math]::Round(($cs.TotalPhysicalMemory/1GB),2);
        ProcessorCount=@($cpu).Count; MemoryModuleCount=@($mem).Count; CollectionTime=Get-Date
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
    Add-CollectionStatus 'Core hardware inventory' 'Collected' 'WMI/CIM inventory exported.'
    if($cs.Manufacturer -notmatch 'HPE|Hewlett|HP'){ Add-Finding INFORMATIONAL 'Platform' "Manufacturer reported as '$($cs.Manufacturer)'" 'The system did not identify itself as an HPE/Hewlett-Packard platform through Win32_ComputerSystem.' }
    if($bios.ReleaseDate -and ([datetime]$bios.ReleaseDate -lt (Get-Date).AddYears(-5))){ Add-Finding INFORMATIONAL 'Lifecycle' "BIOS release date: $($bios.ReleaseDate)" 'Old firmware/platform age increases lifecycle and support risk, but age alone does not prove imminent hardware failure.' }
} catch { Write-Log "Core inventory failure: $($_.Exception.Message)" FAIL; Add-CollectionStatus 'Core hardware inventory' 'Failed' $_.Exception.Message }

# Storage cmdlets / reliability data
try {
    if(Get-Command Get-PhysicalDisk -ErrorAction SilentlyContinue){
        $pd = @(Get-PhysicalDisk -ErrorAction Stop | Select-Object FriendlyName,SerialNumber,MediaType,BusType,HealthStatus,OperationalStatus,Size,Usage,CanPool)
        Export-SafeCsv $pd (Join-Path $Root '09-GetPhysicalDisk.csv') | Out-Null
        foreach($d in $pd){ if(($d.HealthStatus -and $d.HealthStatus -ne 'Healthy') -or (($d.OperationalStatus -join ',') -notmatch '^OK$')){ Add-Finding CRITICAL 'Storage' "Physical disk $($d.FriendlyName): Health=$($d.HealthStatus), Operational=$($d.OperationalStatus -join ',')" 'Windows Storage Management reports a disk that is not healthy/OK. Validate against the RAID controller and HPE IML.' } }
        Add-CollectionStatus 'Windows physical disk health' 'Collected' "$($pd.Count) physical disk record(s)."
        foreach($d in @(Get-PhysicalDisk -ErrorAction SilentlyContinue)){
            try {
                $r = $d | Get-StorageReliabilityCounter -ErrorAction Stop
                $r | Select-Object @{n='FriendlyName';e={$d.FriendlyName}},Temperature,TemperatureMax,ReadErrorsTotal,ReadErrorsUncorrected,WriteErrorsTotal,WriteErrorsUncorrected,Wear,PowerOnHours | Export-Csv -LiteralPath (Join-Path $RawDir ("StorageReliability-{0}.csv" -f (($d.FriendlyName -replace '[^a-zA-Z0-9_-]','_')))) -NoTypeInformation -Encoding UTF8
                if(($r.ReadErrorsUncorrected -as [long]) -gt 0 -or ($r.WriteErrorsUncorrected -as [long]) -gt 0){ Add-Finding CRITICAL 'Storage' "Uncorrected storage errors reported for $($d.FriendlyName)." 'Uncorrected device errors are a high-priority storage-health indicator.' }
            } catch {}
        }
    } else { Add-CollectionStatus 'Windows physical disk health' 'Unavailable' 'Storage module/Get-PhysicalDisk not available.' }
} catch { Add-CollectionStatus 'Windows physical disk health' 'Unavailable' $_.Exception.Message; Write-Log "Get-PhysicalDisk collection failed: $($_.Exception.Message)" WARN }

# Event evidence
$whea = Get-EventsSafe @{LogName='System';StartTime=$StartTime;ProviderName='Microsoft-Windows-WHEA-Logger'} 'WHEA hardware events'
Export-SafeCsv (Convert-EventRows $whea) (Join-Path $EventDir 'WHEA-Hardware-Errors.csv') | Out-Null
if($whea.Count -gt 0){ Add-Finding WARNING 'Hardware/WHEA' "$($whea.Count) WHEA event(s) found in the last $EventLookbackDays days." 'WHEA records hardware-reported errors. Corrected and uncorrected events require review of the event details and recurrence.' }

$storageProviders = @('disk','storahci','stornvme','storport','iaStorA','iaStorAVC','HpCISSs2','Smart Array','Ntfs','volmgr','volsnap')
$storage = Get-EventsSafe @{LogName='System';StartTime=$StartTime;Level=1,2,3} 'Storage/system error events'
$storage = @($storage | Where-Object { ($storageProviders -contains $_.ProviderName) -or $_.ProviderName -match 'disk|stor|ntfs|vol|array|ciss' })
Export-SafeCsv (Convert-EventRows $storage) (Join-Path $EventDir 'Disk-Storage-Errors.csv') | Out-Null
$criticalStorageIds = @(7,11,15,51,55,98,129,153,157)
$storageKey = @($storage | Where-Object {$criticalStorageIds -contains $_.Id})
if($storageKey.Count -gt 0){ Add-Finding WARNING 'Storage' "$($storageKey.Count) notable disk/storage/filesystem event(s) (IDs 7,11,15,51,55,98,129,153,157) found." 'These IDs can indicate I/O errors, resets, retries, filesystem issues, or device removal. Frequency and message details should be correlated with RAID/IML evidence.' }

$unexpected = Get-EventsSafe @{LogName='System';StartTime=$StartTime;Id=41,6008,1074,6005,6006} 'Shutdown/restart events'
Export-SafeCsv (Convert-EventRows $unexpected) (Join-Path $EventDir 'Unexpected-Shutdowns.csv') | Out-Null
$badShutdown = @($unexpected | Where-Object {$_.Id -in 41,6008})
if($badShutdown.Count -gt 0){ Add-Finding WARNING 'Stability' "$($badShutdown.Count) unexpected shutdown/Kernel-Power event(s) found." 'Unexpected shutdowns can result from power, hardware, OS, or administrative causes and should be correlated with surrounding events and iLO/IML.' }

$bug = Get-EventsSafe @{LogName='System';StartTime=$StartTime;ProviderName='Microsoft-Windows-WER-SystemErrorReporting'} 'Bugcheck events'
if($bug.Count -eq 0){ $bug = Get-EventsSafe @{LogName='System';StartTime=$StartTime;Id=1001} 'System Event ID 1001' }
Export-SafeCsv (Convert-EventRows $bug) (Join-Path $EventDir 'BugChecks.csv') | Out-Null
if($bug.Count -gt 0){ Add-Finding WARNING 'Stability' "$($bug.Count) bugcheck/system error event(s) found." 'System crashes warrant review; the event alone does not establish hardware as the cause.' }

$critical = Get-EventsSafe @{LogName='System';StartTime=$StartTime;Level=1} 'Critical System events'
Export-SafeCsv (Convert-EventRows $critical) (Join-Path $EventDir 'Critical-System-Events.csv') | Out-Null

# Raw Windows evidence
Invoke-CaptureCommand 'systeminfo.exe' @() (Join-Path $RawDir 'SystemInfo.txt') | Out-Null
Invoke-CaptureCommand 'driverquery.exe' @('/v') (Join-Path $RawDir 'DriverQuery.txt') | Out-Null
try { Get-HotFix | Sort-Object InstalledOn -Descending | Export-Csv (Join-Path $RawDir 'Installed-Hotfixes.csv') -NoTypeInformation -Encoding UTF8 } catch {}
# Enumerate installed HPE software from uninstall registry only. Do NOT query Win32_Product; it can trigger MSI consistency checks.
try {
    $apps = foreach($key in 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'){
        Get-ItemProperty $key -ErrorAction SilentlyContinue | Where-Object {$_.DisplayName -match 'HPE|Hewlett|HP |Smart Storage|Array|iLO'} | Select-Object DisplayName,DisplayVersion,Publisher,InstallDate
    }
    Export-SafeCsv $apps (Join-Path $RawDir 'Installed-HPE-Software.csv') | Out-Null
} catch { Write-Log "HPE installed-software registry collection failed: $($_.Exception.Message)" WARN }

# HPE detection and local tool capture
$hpeText = New-Object System.Collections.Generic.List[string]
$hpeText.Add("Computer: $Computer") | Out-Null
$hpeText.Add("Manufacturer/Model: $($cs.Manufacturer) $($cs.Model)") | Out-Null
$hpeText.Add("Serial: $($bios.SerialNumber)") | Out-Null
$hpeCandidates = @(
    'C:\Program Files\Smart Storage Administrator\ssacli\bin\ssacli.exe',
    'C:\Program Files\Smart Storage Administrator\ssacli\bin\hpssacli.exe',
    'C:\Program Files\HP\hpssacli\bin\hpssacli.exe',
    'C:\Program Files\Compaq\Hpacucli\Bin\hpacucli.exe',
    'C:\Program Files\Hewlett-Packard\Array Configuration Utility\Bin\hpacucli.exe'
)
$ssa = $hpeCandidates | Where-Object {Test-Path $_} | Select-Object -First 1
if($ssa){
    $hpeText.Add("Smart Array CLI detected: $ssa") | Out-Null
    try {
        & $ssa 'ctrl' 'all' 'show' 'status' 2>&1 | Out-File (Join-Path $HpeDir 'SmartArray-Controller-Status.txt') -Width 4096 -Encoding utf8
        & $ssa 'ctrl' 'all' 'show' 'config' 'detail' 2>&1 | Out-File (Join-Path $HpeDir 'SmartArray-Configuration-Detail.txt') -Width 4096 -Encoding utf8
        & $ssa 'ctrl' 'all' 'pd' 'all' 'show' 'detail' 2>&1 | Out-File (Join-Path $HpeDir 'SmartArray-PhysicalDrives-Detail.txt') -Width 4096 -Encoding utf8
        & $ssa 'ctrl' 'all' 'ld' 'all' 'show' 'detail' 2>&1 | Out-File (Join-Path $HpeDir 'SmartArray-LogicalDrives-Detail.txt') -Width 4096 -Encoding utf8
        Add-CollectionStatus 'HPE Smart Array CLI' 'Collected' $ssa
        $statusText = Get-Content (Join-Path $HpeDir 'SmartArray-Controller-Status.txt') -Raw -ErrorAction SilentlyContinue
        $configText = Get-Content (Join-Path $HpeDir 'SmartArray-Configuration-Detail.txt') -Raw -ErrorAction SilentlyContinue
        if(($statusText+$configText) -match '(?im)\b(Failed|Degraded|Predictive Failure|Interim Recovery Mode|Recovering|Rebuilding)\b'){ Add-Finding CRITICAL 'HPE Smart Array' 'Smart Array output contains a failed/degraded/predictive/recovery state.' 'This is direct controller-level evidence requiring immediate review and protection of critical data.' }
    } catch { Add-CollectionStatus 'HPE Smart Array CLI' 'Failed' $_.Exception.Message; $hpeText.Add("Smart Array collection error: $($_.Exception.Message)") | Out-Null }
} else { Add-CollectionStatus 'HPE Smart Array CLI' 'Unavailable' 'No known SSA/ACU CLI executable found.'; $hpeText.Add('Smart Array CLI: not detected locally.') | Out-Null }

# HPE WMI namespaces/classes if agents/providers are installed.
try {
    $namespaces = @(Get-CimInstance -Namespace root -ClassName __Namespace -ErrorAction Stop | Where-Object {$_.Name -match 'hp|hpe'} | Select-Object -ExpandProperty Name)
    $hpeText.Add('Root HPE/HP WMI namespaces: ' + ($namespaces -join ', ')) | Out-Null
    foreach($ns in $namespaces){
        try { Get-CimClass -Namespace ("root\$ns") -ErrorAction Stop | Select-Object CimClassName,CimClassMethods,CimClassProperties | Export-Clixml (Join-Path $HpeDir ("WMI-Classes-root-{0}.xml" -f $ns)) }
        catch {}
    }
    if($namespaces.Count){Add-CollectionStatus 'HPE WMI providers' 'Detected' ($namespaces -join ', ')}else{Add-CollectionStatus 'HPE WMI providers' 'Unavailable' 'No HP/HPE root WMI namespace detected.'}
} catch { Add-CollectionStatus 'HPE WMI providers' 'Unavailable' $_.Exception.Message }

# HP/HPE-related Windows events across available logs, limited to logs with records.
try {
    $hpeLogs = @(Get-WinEvent -ListLog * -ErrorAction SilentlyContinue | Where-Object {$_.LogName -match 'HP|HPE|iLO|Smart Array' -and $_.RecordCount -gt 0} | Select-Object -ExpandProperty LogName)
    $hpeText.Add('HPE-related event logs: ' + ($hpeLogs -join ', ')) | Out-Null
    foreach($log in $hpeLogs){
        $safe = $log -replace '[\\/:*?"<>|]','_'
        $hev = Get-EventsSafe @{LogName=$log;StartTime=$StartTime} ("HPE log $log")
        Export-SafeCsv (Convert-EventRows $hev) (Join-Path $HpeDir ("EventLog-{0}.csv" -f $safe)) | Out-Null
    }
} catch { Write-Log "HPE event log discovery failed: $($_.Exception.Message)" WARN }
Set-Content -LiteralPath (Join-Path $HpeDir 'HPE-Software-and-Interfaces-Detected.txt') -Value $hpeText -Encoding UTF8

# Services and drivers that may expose HPE/storage health
try {
    Get-CimInstance Win32_Service | Where-Object {$_.Name -match 'hp|hpe|ilo|array|stor' -or $_.DisplayName -match 'HPE|Hewlett|iLO|Smart Array'} | Select-Object Name,DisplayName,State,StartMode,PathName | Export-Csv (Join-Path $HpeDir 'HPE-Related-Services.csv') -NoTypeInformation -Encoding UTF8
    Get-CimInstance Win32_SystemDriver | Where-Object {$_.Name -match 'hp|hpe|ciss|stor' -or $_.DisplayName -match 'HPE|Hewlett|Smart Array'} | Select-Object Name,DisplayName,State,StartMode,PathName | Export-Csv (Join-Path $HpeDir 'HPE-Storage-Related-Drivers.csv') -NoTypeInformation -Encoding UTF8
} catch {}

# Summary
$Findings | Export-Csv -LiteralPath (Join-Path $Root 'Findings.csv') -NoTypeInformation -Encoding UTF8
$Collection | Export-Csv -LiteralPath (Join-Path $Root 'Collection-Status.csv') -NoTypeInformation -Encoding UTF8
$critCount = @($Findings | Where-Object Severity -eq 'CRITICAL').Count
$warnCount = @($Findings | Where-Object Severity -eq 'WARNING').Count
$infoCount = @($Findings | Where-Object Severity -eq 'INFORMATIONAL').Count
$summary = New-Object System.Collections.Generic.List[string]
$summary.Add('RESILIENT IT - SERVER HARDWARE HEALTH EVIDENCE SUMMARY') | Out-Null
$summary.Add(('='*70)) | Out-Null
$summary.Add("Computer: $Computer") | Out-Null
$summary.Add("Platform: $($cs.Manufacturer) $($cs.Model)") | Out-Null
$summary.Add("Serial Number: $($bios.SerialNumber)") | Out-Null
$summary.Add("Collected: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')") | Out-Null
$summary.Add("Lookback: $EventLookbackDays days") | Out-Null
$summary.Add("Collector version: $ScriptVersion") | Out-Null
$summary.Add('') | Out-Null
$summary.Add("Finding counts: CRITICAL=$critCount  WARNING=$warnCount  INFORMATIONAL=$infoCount") | Out-Null
$summary.Add('') | Out-Null
$summary.Add('IMPORTANT: Findings are evidence indicators, not an automatic diagnosis. Correlate Windows evidence with HPE iLO Integrated Management Log (IML), Active Health System (AHS), and Smart Array status before making a hardware-failure determination.') | Out-Null
$summary.Add('') | Out-Null
$summary.Add('FINDINGS') | Out-Null
$summary.Add(('-'*70)) | Out-Null
if($Findings.Count -eq 0){$summary.Add('No automatically classified findings were detected. This does NOT establish that the hardware is healthy; review Collection-Status.csv and obtain iLO IML/AHS evidence.') | Out-Null}
foreach($f in $Findings){$summary.Add("[$($f.Severity)] $($f.Category): $($f.Evidence)") | Out-Null; $summary.Add("  Interpretation: $($f.Meaning)") | Out-Null}
$summary.Add('') | Out-Null
$summary.Add('COLLECTION COVERAGE') | Out-Null
$summary.Add(('-'*70)) | Out-Null
foreach($c in $Collection){$summary.Add("[$($c.Status)] $($c.Area): $($c.Detail)") | Out-Null}
Set-Content -LiteralPath (Join-Path $Root '00-Executive-Summary.txt') -Value $summary -Encoding UTF8

# Manifest hashes before ZIP
try {
    Get-ChildItem -LiteralPath $Root -File -Recurse | Get-FileHash -Algorithm SHA256 | Select-Object Path,Hash,Algorithm | Export-Csv (Join-Path $Root 'Evidence-SHA256-Manifest.csv') -NoTypeInformation -Encoding UTF8
} catch { Write-Log "Hash manifest failed: $($_.Exception.Message)" WARN }

try {
    if(Test-Path $ZipPath){Remove-Item $ZipPath -Force}
    Compress-Archive -Path (Join-Path $Root '*') -DestinationPath $ZipPath -CompressionLevel Optimal -Force
    Write-Log "Evidence ZIP created: $ZipPath" PASS
} catch { Write-Log "ZIP creation failed: $($_.Exception.Message)" FAIL }

try { Stop-Transcript | Out-Null } catch {}
Write-Log "Collection complete. CRITICAL=$critCount WARNING=$warnCount INFORMATIONAL=$infoCount" PASS
Write-Output "OUTPUT_FOLDER=$Root"
if(Test-Path $ZipPath){Write-Output "OUTPUT_ZIP=$ZipPath"; exit 0}else{exit 1}
