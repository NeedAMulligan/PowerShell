#Requires -Version 5.1
<#
.SYNOPSIS
  Removes remaining ConnectSecure/CyberCNS Windows agent components.
.DESCRIPTION
  Intended for retired ConnectSecure installations; works as administrator or SYSTEM.
  Does not remove generic osquery/nmap executables outside vendor paths.
  Backs up uninstall registry keys, writes TXT/CSV logs, and verifies leftovers.
  No reboot is initiated. Some locked services/files may need a later reboot.
.NOTES
  Run via 64-bit Windows PowerShell 5.1 where possible.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$OutDir = 'C:\Temp'
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$LogPath = Join-Path $OutDir "ConnectSecure-FullPurge-$env:COMPUTERNAME-$Stamp.log"
$CsvPath = Join-Path $OutDir "ConnectSecure-FullPurge-$env:COMPUTERNAME-$Stamp.csv"
$RegBackupDir = Join-Path $OutDir "ConnectSecure-RegistryBackup-$env:COMPUTERNAME-$Stamp"
New-Item -ItemType Directory -Path $RegBackupDir -Force | Out-Null
$script:Entries = New-Object 'System.Collections.Generic.List[object]'
$script:Failures = 0
function Record([string]$Type,[string]$Target,[string]$Status,[string]$Detail='') {
    $e = [pscustomobject]@{Timestamp=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss');Computer=$env:COMPUTERNAME;Type=$Type;Target=$Target;Status=$Status;Detail=$Detail}
    $script:Entries.Add($e)
    $line = '{0} [{1}] {2}: {3} - {4}' -f $e.Timestamp,$Status,$Type,$Target,$Detail
    Add-Content -LiteralPath $LogPath -Value $line
    Write-Host $line
    if ($Status -eq 'ERROR') { $script:Failures++ }
}
function MatchesAgent([string]$s) { return ($s -match '(?i)CyberCNS|ConnectSecure') }
function FindServices {
    @(Get-CimInstance -ClassName Win32_Service | Where-Object {
       (MatchesAgent $_.Name) -or (MatchesAgent $_.DisplayName) -or (MatchesAgent $_.PathName)
    })
}
function FindProcesses {
    @(Get-CimInstance -ClassName Win32_Process | Where-Object {
       ($_.Name -match '(?i)^(cybercnsagent|cybercnsagentv2|cybercnsagentmonitor|connectsecureagentmonitor|cyberutilities)(\.exe)?$') -or
       ($_.ExecutablePath -match '(?i)\\(CyberCNSAgent|CyberCNSAgentV2|CyberCNS)\\')
    })
}
function FindTasks {
    @(Get-ScheduledTask | Where-Object {
      (MatchesAgent $_.TaskName) -or (MatchesAgent $_.TaskPath) -or
      (MatchesAgent (($_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join ' '))
    })
}
Record 'Session' 'Start' 'INFO' "Identity=$([Security.Principal.WindowsIdentity]::GetCurrent().Name); PowerShell=$($PSVersionTable.PSVersion); Is64Bit=$([Environment]::Is64BitProcess)"
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Record 'Session' 'Elevation' 'ERROR' 'Administrator or SYSTEM privileges required'
    $script:Entries | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
    exit 2
}
# Stop vendor processes before removing vendor services and installation files.
try {
    foreach ($p in @(FindProcesses)) {
        try { Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop; Record 'Process' "$($p.Name) PID $($p.ProcessId)" 'REMOVED' 'Stopped' }
        catch { Record 'Process' "$($p.Name) PID $($p.ProcessId)" 'ERROR' $_.Exception.Message }
    }
} catch { Record 'ProcessEnumeration' 'Win32_Process' 'ERROR' $_.Exception.Message }
try {
    foreach ($svc in @(FindServices)) {
        try {
            if ($svc.State -ne 'Stopped') {
                & sc.exe stop $svc.Name 2>&1 | Out-Null
                Start-Sleep -Seconds 2
            }
            $msg = (& sc.exe delete $svc.Name 2>&1 | Out-String).Trim()
            $code = $LASTEXITCODE
            if ($code -eq 0 -or $msg -match 'marked for deletion') { Record 'Service' $svc.Name 'REMOVED' $msg }
            else { Record 'Service' $svc.Name 'ERROR' "Exit=$code; $msg" }
        } catch { Record 'Service' $svc.Name 'ERROR' $_.Exception.Message }
    }
} catch { Record 'ServiceEnumeration' 'Win32_Service' 'ERROR' $_.Exception.Message }
try {
    foreach ($task in @(FindTasks)) {
        try { Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false -ErrorAction Stop; Record 'Task' "$($task.TaskPath)$($task.TaskName)" 'REMOVED' }
        catch { Record 'Task' "$($task.TaskPath)$($task.TaskName)" 'ERROR' $_.Exception.Message }
    }
} catch { Record 'TaskEnumeration' 'ScheduledTasks' 'ERROR' $_.Exception.Message }
# Delete exact product uninstall registrations in both registry views, backing them up.
$uninstall = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64,[Microsoft.Win32.RegistryView]::Registry32)) {
    try {
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,$view)
        $parent = $base.OpenSubKey($uninstall,$true)
        if ($null -eq $parent) { $base.Close(); continue }
        foreach ($sub in @($parent.GetSubKeyNames())) {
            $key = $parent.OpenSubKey($sub)
            if ($null -eq $key) { continue }
            $name = [string]$key.GetValue('DisplayName','')
            $install = [string]$key.GetValue('InstallLocation','')
            $uninstallCmd = [string]$key.GetValue('UninstallString','')
            $key.Close()
            if ($sub -notmatch '(?i)CyberCNS|ConnectSecure' -and
                $name -notmatch '(?i)CyberCNS|ConnectSecure' -and
                $install -notmatch '(?i)CyberCNSAgent' -and
                $uninstallCmd -notmatch '(?i)CyberCNSAgent') { continue }
            $keyId = "$view\$uninstall\$sub"
            try {
                $native = if ($view -eq [Microsoft.Win32.RegistryView]::Registry32) { 'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\' + $sub } else { 'HKLM\' + $uninstall + '\' + $sub }
                $safe = ($sub -replace '[^a-zA-Z0-9_-]','_')
                $backup = Join-Path $RegBackupDir "Uninstall-$view-$safe.reg"
                & reg.exe export $native $backup /y 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $backup)) { throw "Registry backup failed for $native" }
                $parent.DeleteSubKeyTree($sub,$false)
                Record 'UninstallRegistry' $keyId 'REMOVED' "Backup=$backup; DisplayName=$name"
            } catch { Record 'UninstallRegistry' $keyId 'ERROR' $_.Exception.Message }
        }
        $parent.Close(); $base.Close()
    } catch { Record 'RegistryEnumeration' "$view" 'ERROR' $_.Exception.Message }
}
# Remove only exact, known agent folders; do not delete parent folders.
$folders = @(
    'C:\Program Files (x86)\CyberCNSAgent',
    'C:\Program Files (x86)\CyberCNSAgentV2',
    'C:\Program Files (x86)\CyberCNS',
    'C:\Program Files\CyberCNSAgent',
    'C:\Program Files\CyberCNSAgentV2',
    'C:\Program Files\CyberCNS',
    'C:\ProgramData\CyberCNSAgent',
    'C:\ProgramData\CyberCNSAgentV2',
    'C:\ProgramData\CyberCNS',
    'C:\ProgramData\ConnectSecure'
)
foreach ($folder in $folders) {
    try {
        if (Test-Path -LiteralPath $folder) {
            $item = Get-Item -LiteralPath $folder -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse point detected; not following it' }
            Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction Stop
            Record 'Folder' $folder 'REMOVED'
        } else { Record 'Folder' $folder 'ABSENT' }
    } catch { Record 'Folder' $folder 'ERROR' $_.Exception.Message }
}
# Post-removal verification. Report anything still requiring attention.
try { foreach ($s in @(FindServices)) { Record 'VerifyService' $s.Name 'REMAINS' $s.PathName } } catch { Record 'VerifyServices' 'Win32_Service' 'ERROR' $_.Exception.Message }
try { foreach ($p in @(FindProcesses)) { Record 'VerifyProcess' "$($p.Name) PID $($p.ProcessId)" 'REMAINS' $p.ExecutablePath } } catch { Record 'VerifyProcesses' 'Win32_Process' 'ERROR' $_.Exception.Message }
try { foreach ($t in @(FindTasks)) { Record 'VerifyTask' "$($t.TaskPath)$($t.TaskName)" 'REMAINS' } } catch { Record 'VerifyTasks' 'ScheduledTasks' 'ERROR' $_.Exception.Message }
foreach ($folder in $folders) { if (Test-Path -LiteralPath $folder) { Record 'VerifyFolder' $folder 'REMAINS' } }
foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64,[Microsoft.Win32.RegistryView]::Registry32)) {
    try {
        $b = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,$view)
        $p = $b.OpenSubKey($uninstall)
        if ($null -ne $p) {
            foreach ($sub in @($p.GetSubKeyNames())) {
                $k = $p.OpenSubKey($sub)
                if ($null -eq $k) { continue }
                $n = [string]$k.GetValue('DisplayName','')
                $u = [string]$k.GetValue('UninstallString','')
                $i = [string]$k.GetValue('InstallLocation','')
                $k.Close()
                if ($sub -match '(?i)CyberCNS|ConnectSecure' -or $n -match '(?i)CyberCNS|ConnectSecure' -or $u -match '(?i)CyberCNSAgent' -or $i -match '(?i)CyberCNSAgent') {
                    Record 'VerifyUninstallRegistry' "$view\$sub" 'REMAINS' $n
                }
            }
            $p.Close()
        }
        $b.Close()
    } catch { Record 'VerifyRegistry' "$view" 'ERROR' $_.Exception.Message }
}
$remaining = @($script:Entries | Where-Object Status -eq 'REMAINS').Count
if ($script:Failures -gt 0 -or $remaining -gt 0) {
    Record 'Summary' $env:COMPUTERNAME 'INCOMPLETE' "Errors=$($script:Failures); Remaining=$remaining; reboot may be required for pending service deletion"
    $exitCode = 1
} else {
    Record 'Summary' $env:COMPUTERNAME 'SUCCESS' 'No matching services, processes, tasks, uninstall entries or targeted agent folders detected'
    $exitCode = 0
}
$script:Entries | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8
Write-Host "Log: $LogPath"
Write-Host "CSV: $CsvPath"
Write-Host "Registry backup: $RegBackupDir"
exit $exitCode
