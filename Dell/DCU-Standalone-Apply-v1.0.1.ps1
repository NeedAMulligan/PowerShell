#requires -Version 5.1
<#
.SYNOPSIS
  Isolated Dell Command | Update approved-driver installation pilot.
.DESCRIPTION
  Runs a fresh DCU /scan with the explicit bios,firmware,driver filter, parses
  Dell's XML report, and only permits /applyUpdates if every applicable update
  is a Driver and its Dell release ID matches the approved pilot allowlist.
  The actual installation requires -Execute. Reboots are disabled; no DCU
  installation, configuration changes, or master prep tasks are performed.
  Dell's automatic schedule is NOT changed by this script.
.NOTES
  Version 1.0.1. Windows PowerShell 5.1; elevated administrator required.
  Pilot allowlist from 2026-11-09: WKT42 (Intel), 9AYC6 (Cirrus Audio).
.EXAMPLE
  .\RB-DCU-Standalone-Apply-Test-v1.0.1.ps1
.EXAMPLE
  .\RB-DCU-Standalone-Apply-Test-v1.0.1.ps1 -Execute
#>
[CmdletBinding()]
param(
    [switch]$Execute,
    [string]$OutputRoot = 'C:\Temp',
    [string[]]$ApprovedReleaseIds = @('WKT42','9AYC6'),
    [int]$TimeoutMinutes = 90
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$folder = Join-Path $OutputRoot ('RB-DCU-Apply-{0}-{1}' -f $env:COMPUTERNAME,$stamp)
$scanReportDir = Join-Path $folder 'PreScanReport'
New-Item -ItemType Directory -Path $scanReportDir -Force | Out-Null
$log = Join-Path $folder 'Apply-Test.log'
$json = Join-Path $folder 'Apply-Test.json'
$csv = Join-Path $folder 'Approved-Updates.csv'
$scanNative = Join-Path $folder 'DCU-PreScan.log'
$applyNative = Join-Path $folder 'DCU-Apply.log'
$postNative = Join-Path $folder 'DCU-PostScan.log'
$cli = 'C:\Program Files\Dell\CommandUpdate\dcu-cli.exe'
$summary = [ordered]@{
    Script='RB-DCU-Standalone-Apply-Test';Version='1.0.1'
    Computer=$env:COMPUTERNAME;Started=(Get-Date).ToString('o');ExecuteRequested=[bool]$Execute
    ApprovedReleaseIds=@($ApprovedReleaseIds);Cli=$cli;CliVersion=$null
    PendingRebootBefore=$null;PreScanExitCode=$null;PreScanUpdates=@();ApprovalStatus='NOT_EVALUATED'
    ApplyExitCode=$null;ApplyStatus='NOT_RUN';PostScanExitCode=$null;PostScanUpdates=@()
    PendingRebootAfter=$null;Warnings=@();Errors=@();Folder=$folder;Finished=$null
}
function Write-Log([string]$message,[string]$level='INFO') {
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$level,$message
    Add-Content -LiteralPath $log -Encoding UTF8 -Value $line
    Write-Host $line
}
function Get-PendingReboot {
    $cbs = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    $wu = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    $count=0
    try {
        $entries=(Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
        if ($null -ne $entries) { $count=@($entries).Count }
    } catch {}
    [pscustomobject]@{CBS=$cbs;WindowsUpdate=$wu;PendingFileRenameEntries=$count;Any=($cbs -or $wu -or $count -gt 0)}
}
function Invoke-DCU([string]$label,[string[]]$arguments,[int]$timeout) {
    $stdout=Join-Path $folder ($label+'-stdout.txt')
    $stderr=Join-Path $folder ($label+'-stderr.txt')
    Write-Log ('EXEC {0}: "{1}" {2}' -f $label,$cli,($arguments -join ' '))
    $p=Start-Process -FilePath $cli -ArgumentList $arguments -WorkingDirectory (Split-Path -Parent $cli) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    $deadline=(Get-Date).AddMinutes($timeout)
    while (-not $p.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 2; $p.Refresh() }
    if (-not $p.HasExited) {
        Write-Log ('TIMEOUT {0}: process PID {1} exceeded {2} minutes.' -f $label,$p.Id,$timeout) 'FAIL'
        try { Stop-Process -Id $p.Id -Force -ErrorAction Stop } catch { Write-Log ('Unable to stop process: '+$_.Exception.Message) 'WARN' }
        throw ('DCU {0} timed out. Installer child processes may still exist; inspect before retrying.' -f $label)
    }
    $p.WaitForExit();$p.Refresh()
    $exit=[int]$p.ExitCode
    Write-Log ('RESULT {0}: exit code {1}' -f $label,$exit)
    foreach ($path in @($stdout,$stderr)) {
        if (Test-Path -LiteralPath $path) {
            foreach ($line in @(Get-Content -LiteralPath $path -ErrorAction SilentlyContinue | Select-Object -Last 50)) {
                if (-not [string]::IsNullOrWhiteSpace($line)) { Write-Log ('{0}: {1}' -f (Split-Path -Leaf $path),$line) }
            }
        }
    }
    return $exit
}
function Read-DellReport([string]$directory) {
    $files=@(Get-ChildItem -LiteralPath $directory -Filter '*.xml' -File -Recurse -ErrorAction SilentlyContinue)
    if ($files.Count -ne 1) { throw ('Expected exactly one DCU XML report, received {0}.' -f $files.Count) }
    $doc=New-Object System.Xml.XmlDocument
    $doc.Load($files[0].FullName)
    if ($null -eq $doc.DocumentElement -or $doc.DocumentElement.LocalName -ine 'updates') { throw 'Unknown Dell XML report root element.' }
    $nodes=@($doc.DocumentElement.SelectNodes('./update'))
    $results=New-Object 'System.Collections.Generic.List[object]'
    foreach ($n in $nodes) {
        $id=[string]$n.SelectSingleNode('release').InnerText
        $name=[string]$n.SelectSingleNode('name').InnerText
        $type=[string]$n.SelectSingleNode('type').InnerText
        $category=[string]$n.SelectSingleNode('category').InnerText
        $version=[string]$n.SelectSingleNode('version').InnerText
        $urgency=[string]$n.SelectSingleNode('urgency').InnerText
        if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($type)) { throw 'Dell update report has an incomplete update node.' }
        $results.Add([pscustomobject]@{ReleaseID=$id;Name=$name;Version=$version;Type=$type;Category=$category;Urgency=$urgency})
    }
    # PowerShell functions enumerate pipeline outputs. Do not use unary comma here:
    # it wraps the entire collection as one object, which makes the approval
    # gate see System.Object[] instead of individual Dell update records.
    foreach ($record in $results) { Write-Output $record }
}
try {
    Write-Log ('Starting DCU isolated apply pilot. Execute={0}. No automatic reboot.' -f [bool]$Execute)
    $principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Launch elevated Windows PowerShell 5.1.' }
    if (-not (Test-Path -LiteralPath $cli)) { throw 'DCU CLI missing; will not install or repair DCU.' }
    $summary.CliVersion=(Get-Item -LiteralPath $cli).VersionInfo.FileVersion
    $summary.PendingRebootBefore=Get-PendingReboot
    Write-Log ('DCU CLI version={0}; pending reboot={1}' -f $summary.CliVersion,$summary.PendingRebootBefore.Any)
    if ($summary.PendingRebootBefore.Any) { throw 'Pending reboot detected. Reboot before attempting pilot driver installations.' }
    $expected=@($ApprovedReleaseIds | ForEach-Object { $_.Trim().ToUpperInvariant() } | Where-Object { $_ } | Select-Object -Unique)
    if ($expected.Count -eq 0) { throw 'The approved release ID list is empty.' }
    # Fail closed: no app/utility/other types are permitted by this pilot even though
    # the CLI supports wider filters. The scan must match the explicit approved IDs.
    $scanArgs=@('/scan','-updateType=bios,firmware,driver',('-report={0}' -f $scanReportDir),('-outputLog={0}' -f $scanNative))
    $summary.PreScanExitCode=Invoke-DCU 'PreScan' $scanArgs 30
    if ($summary.PreScanExitCode -ne 0) { throw ('Pre-scan failed (exit {0}); installation blocked.' -f $summary.PreScanExitCode) }
    $updates=@(Read-DellReport $scanReportDir)
    # Strictly validate flattened parser output before approving installations.
    foreach ($item in $updates) {
        if ($item -isnot [pscustomobject] -or
            $item.PSObject.Properties.Name -notcontains 'ReleaseID' -or
            $item.PSObject.Properties.Name -notcontains 'Type') {
            throw 'Invalid parsed update structure; expected individual update records. Installation blocked.'
        }
    }
    $summary.PreScanUpdates=@($updates)
    if ($updates.Count -gt 0) { $updates | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8 }
    else { '"ReleaseID","Name","Version","Type","Category","Urgency"' | Set-Content -LiteralPath $csv -Encoding UTF8 }
    Write-Log ('Pre-scan produced {0} update(s).' -f $updates.Count)
    foreach ($u in $updates) { Write-Log ('UPDATE: {0} | {1} | {2} | {3} | {4}' -f $u.ReleaseID,$u.Name,$u.Version,$u.Type,$u.Urgency) }
    if ($updates.Count -eq 0) {
        $summary.ApprovalStatus='NO_UPDATES';$summary.ApplyStatus='NOT_NEEDED'
        Write-Log 'No applicable updates. No changes made.'
    } else {
        $invalid=@($updates | Where-Object { $_.Type -ine 'Driver' -or ($expected -notcontains $_.ReleaseID.ToUpperInvariant()) })
        $actual=@($updates | ForEach-Object { $_.ReleaseID.ToUpperInvariant() } | Select-Object -Unique)
        $missing=@($expected | Where-Object { $actual -notcontains $_ })
        if ($invalid.Count -gt 0 -or $missing.Count -gt 0 -or $updates.Count -ne $expected.Count) {
            $summary.ApprovalStatus='BLOCKED_MISMATCH'
            throw ('Pre-scan does not exactly match approved Driver release IDs ({0}). Invalid={1}; missing={2}; total={3}. No updates installed.' -f ($expected -join ','),$invalid.Count,($missing -join ','),$updates.Count)
        }
        $summary.ApprovalStatus='APPROVED_EXACT_MATCH'
        Write-Log ('Preflight approved exact driver release IDs: {0}' -f ($expected -join ','))
        if (-not $Execute) {
            $summary.ApplyStatus='DRY_RUN'
            Write-Log 'DRY RUN: No update payloads downloaded or installed. Rerun with -Execute to install the approved driver set.'
        } else {
            # NOTE: Dell /applyUpdates applies all eligible updates matching its filters;
            # it has no release-ID allowlist option. Exact pre-scan matching limits risk,
            # but a concurrent catalog change between scan and apply cannot be ruled out.
            Write-Log 'WARNING: /applyUpdates is filtered by type, not by release ID; Dell may refresh applicability.' 'WARN'
            $summary.Warnings += 'Dell apply does not support release-ID allowlist; pre-scan exact-match gate used.'
            $applyArgs=@('/applyUpdates','-updateType=bios,firmware,driver','-reboot=disable',('-outputLog={0}' -f $applyNative))
            $summary.ApplyExitCode=Invoke-DCU 'ApplyUpdates' $applyArgs $TimeoutMinutes
            if ($summary.ApplyExitCode -eq 0) { $summary.ApplyStatus='EXIT_0_REVIEW_LOG' }
            elseif ($summary.ApplyExitCode -eq 1) { $summary.ApplyStatus='REBOOT_REQUIRED_REVIEW_LOG' }
            else { $summary.ApplyStatus='NONZERO_REVIEW_LOG'; $summary.Warnings += ('Apply exit '+$summary.ApplyExitCode+'; review native log') }
            Write-Log ('Apply status={0}. Do not interpret exit code as per-package verification.' -f $summary.ApplyStatus)
            $summary.PendingRebootAfter=Get-PendingReboot
            Write-Log ('Pending reboot after apply={0}' -f $summary.PendingRebootAfter.Any)
            # Post-scan is informational; cached results or pending reboot may yield
            # misleading applicability and cannot independently certify success.
            $postDir=Join-Path $folder 'PostScanReport'
            New-Item -ItemType Directory -Path $postDir -Force | Out-Null
            try {
                $summary.PostScanExitCode=Invoke-DCU 'PostScan' @('/scan','-updateType=bios,firmware,driver',('-report={0}' -f $postDir),('-outputLog={0}' -f $postNative)) 30
                if ($summary.PostScanExitCode -eq 0) { $summary.PostScanUpdates=@(Read-DellReport $postDir) }
                Write-Log ('Post-scan applicable updates={0}; may be cached or affected by pending reboot.' -f @($summary.PostScanUpdates).Count)
            } catch { $summary.Warnings += ('Post-scan unavailable: '+$_.Exception.Message);Write-Log ('Post-scan unavailable: '+$_.Exception.Message) 'WARN' }
        }
    }
} catch {
    $summary.Errors += $_.Exception.Message
    Write-Log ('BLOCKED/FAIL: '+$_.Exception.Message) 'FAIL'
    if ($summary.ApplyStatus -eq 'NOT_RUN') { $summary.ApplyStatus='BLOCKED' }
} finally {
    if ($null -eq $summary.PendingRebootAfter) { $summary.PendingRebootAfter=Get-PendingReboot }
    $summary.Finished=(Get-Date).ToString('o')
    $summary | ConvertTo-Json -Depth 9 | Out-File -LiteralPath $json -Encoding UTF8
    Write-Log ('Results directory: '+$folder)
    Write-Log ('Summary: '+$json)
}
if (@($summary.Errors).Count -gt 0 -or $summary.ApplyStatus -eq 'NONZERO_REVIEW_LOG') { exit 1 }
exit 0
