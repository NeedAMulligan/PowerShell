#requires -version 5.1
#requires -modules DnsServer
<#
.SYNOPSIS
    Audits and configures Microsoft DNS aging/scavenging, inventories stale dynamic records,
    triggers supported DNS scavenging, and creates before/after evidence reports.

.DESCRIPTION
    Resilient IT production script intended for execution directly on a Windows DNS server / DC
    or through an RMM such as Endpoint Central running as SYSTEM.

    The script does NOT directly delete DNS resource records. It uses the supported Windows DNS
    aging/scavenging mechanism. Static records (timestamp 0) are reported but are not scavenged.

    Defaults:
      - No-refresh interval: 7 days
      - Refresh interval:    7 days
      - Server scavenging:   7 days

    By default, eligible AD-integrated primary zones are configured for aging and the local DNS
    server is configured for scavenging. In multi-DNS-server environments, use -ScavengingServer
    to intentionally select the server that should perform scavenging.

.PARAMETER ScavengingServer
    DNS server that should be configured to perform scavenging. Defaults to the local computer.
    When a different server is specified, this script must be able to remotely manage that server.

.PARAMETER NoRefreshDays
    DNS no-refresh interval in days. Default: 7.

.PARAMETER RefreshDays
    DNS refresh interval in days. Default: 7.

.PARAMETER ScavengingIntervalDays
    DNS server scavenging interval in days. Default: 7.

.PARAMETER IncludeReverseZones
    Include reverse lookup zones. Enabled by default. Specify -IncludeReverseZones:$false to skip.

.PARAMETER IncludeZone
    Optional zone names to process. If omitted, eligible AD-integrated primary zones are discovered.

.PARAMETER ExcludeZone
    Additional zones to exclude.

.PARAMETER AuditOnly
    Perform inventory/reporting only. Do not change settings or trigger scavenging.

.PARAMETER OutputPath
    Report/log directory. Default: C:\Temp.

.EXAMPLE
    .\Invoke-RIT-DNS-AgingScavenging-v1.0.1.ps1

.EXAMPLE
    .\Invoke-RIT-DNS-AgingScavenging-v1.0.1.ps1 -ScavengingServer COR-DC01

.EXAMPLE
    .\Invoke-RIT-DNS-AgingScavenging-v1.0.1.ps1 -AuditOnly

.NOTES
    Author: Resilient IT
    Version: 1.0.2
    Requires: Windows PowerShell 5.1, DnsServer module, administrative DNS permissions.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ScavengingServer = $env:COMPUTERNAME,

    [Parameter()]
    [ValidateRange(1,365)]
    [int]$NoRefreshDays = 7,

    [Parameter()]
    [ValidateRange(1,365)]
    [int]$RefreshDays = 7,

    [Parameter()]
    [ValidateRange(1,365)]
    [int]$ScavengingIntervalDays = 7,

    [Parameter()]
    [bool]$IncludeReverseZones = $true,

    [Parameter()]
    [string[]]$IncludeZone,

    [Parameter()]
    [string[]]$ExcludeZone = @(),

    [Parameter()]
    [switch]$AuditOnly,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = 'C:\Temp'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$Script:ExitCode = 0
$Script:Errors = @()
$Script:Changes = @()
$Script:StartTime = Get-Date
$Script:TimeStamp = $Script:StartTime.ToString('yyyyMMdd_HHmmss')
$Script:ComputerName = $env:COMPUTERNAME

if (-not (Test-Path -LiteralPath $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

$Script:LogFile = Join-Path $OutputPath ("DNS-AgingScavenging_{0}_{1}.log" -f $Script:ComputerName,$Script:TimeStamp)
$Script:BeforeCsv = Join-Path $OutputPath ("DNS-Records-Before_{0}_{1}.csv" -f $Script:ComputerName,$Script:TimeStamp)
$Script:StaleCsv = Join-Path $OutputPath ("DNS-Stale-Candidates-Before_{0}_{1}.csv" -f $Script:ComputerName,$Script:TimeStamp)
$Script:AfterCsv = Join-Path $OutputPath ("DNS-Records-After_{0}_{1}.csv" -f $Script:ComputerName,$Script:TimeStamp)
$Script:ZoneCsv = Join-Path $OutputPath ("DNS-Zone-Aging_{0}_{1}.csv" -f $Script:ComputerName,$Script:TimeStamp)
$Script:SummaryJson = Join-Path $OutputPath ("DNS-AgingScavenging-Summary_{0}_{1}.json" -f $Script:ComputerName,$Script:TimeStamp)

function Write-RITLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','PASS','WARN','FAIL','CHANGE')][string]$Level = 'INFO'
    )
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Level,$Message
    Write-Host $line
    try { Add-Content -LiteralPath $Script:LogFile -Value $line -Encoding UTF8 } catch { }
}

function Add-RITError {
    param([string]$Message)
    $Script:Errors += $Message
    if ($Script:ExitCode -lt 2) { $Script:ExitCode = 2 }
    Write-RITLog -Level FAIL -Message $Message
}

function Convert-DnsTimestamp {
    param([object]$Timestamp)
    if ($null -eq $Timestamp) { return $null }
    try {
        if ($Timestamp -is [datetime]) { return [datetime]$Timestamp }
        $hours = [int64]$Timestamp
        if ($hours -le 0) { return $null }
        return [datetime]::FromFileTimeUtc(0).AddHours($hours).ToLocalTime()
    } catch { return $null }
}

function Get-RITEligibleZones {
    param([string]$Server)
    $zones = @(Get-DnsServerZone -ComputerName $Server -ErrorAction Stop)
    $result = foreach ($z in $zones) {
        $name = [string]$z.ZoneName
        if ($IncludeZone -and ($IncludeZone -notcontains $name)) { continue }
        if ($ExcludeZone -contains $name) { continue }
        if ($name -eq 'TrustAnchors') { continue }
        if ($name -match '^_msdcs\.') { continue }
        if ($name -match '^(0|127|255)\.in-addr\.arpa$') { continue }
        if (-not $IncludeReverseZones -and ($z.IsReverseLookupZone -eq $true)) { continue }
        if ($z.ZoneType -ne 'Primary') { continue }
        if ($z.IsDsIntegrated -ne $true) { continue }
        $z
    }
    return @($result)
}

function Get-RITRecordInventory {
    param(
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory)][array]$Zones,
        [Parameter(Mandatory)][timespan]$NoRefresh,
        [Parameter(Mandatory)][timespan]$Refresh
    )
    $now = Get-Date
    $staleWindow = $NoRefresh + $Refresh
    $rows = @()
    foreach ($zone in $Zones) {
        Write-RITLog "Inventorying DNS records in zone '$($zone.ZoneName)' on $Server."
        try {
            $records = @(Get-DnsServerResourceRecord -ComputerName $Server -ZoneName $zone.ZoneName -ErrorAction Stop)
            foreach ($r in $records) {
                $ts = $null
                try { $ts = Convert-DnsTimestamp -Timestamp $r.Timestamp } catch { }
                $isStatic = ($null -eq $ts)
                $staleAfter = if ($ts) { $ts.Add($staleWindow) } else { $null }
                $ageDays = if ($ts) { [math]::Round(($now - $ts).TotalDays,2) } else { $null }
                $candidate = ($ts -and $staleAfter -le $now)
                $data = $null
                try { $data = ($r.RecordData | Out-String).Trim() } catch { $data = [string]$r.RecordData }
                $rows += [pscustomobject]@{
                    Server                 = $Server
                    Zone                   = $zone.ZoneName
                    HostName               = $r.HostName
                    RecordType             = $r.RecordType
                    RecordData             = $data
                    Timestamp              = $ts
                    IsStatic               = $isStatic
                    AgeDays                = $ageDays
                    StaleAfter             = $staleAfter
                    StaleCandidateByAge     = [bool]$candidate
                    CalculatedAt            = $now
                }
            }
        } catch {
            Add-RITError "Unable to inventory zone '$($zone.ZoneName)': $($_.Exception.Message)"
        }
    }
    Write-Output $rows
}

Write-RITLog "Starting Resilient IT DNS aging/scavenging assessment v1.0.2."
Write-RITLog "Running as $([Security.Principal.WindowsIdentity]::GetCurrent().Name); local computer $Script:ComputerName; target scavenging server $ScavengingServer."
Write-RITLog "Configured intervals: NoRefresh=$NoRefreshDays days; Refresh=$RefreshDays days; Scavenging=$ScavengingIntervalDays days."
if ($AuditOnly) { Write-RITLog -Level WARN -Message 'AuditOnly is enabled. No DNS configuration changes or scavenging will be performed.' }

try {
    Import-Module DnsServer -ErrorAction Stop
    Write-RITLog -Level PASS -Message 'DnsServer PowerShell module loaded.'
} catch {
    Add-RITError "DnsServer PowerShell module is unavailable: $($_.Exception.Message)"
    exit $Script:ExitCode
}

try {
    # Do not use Get-DnsServer as the health probe. On some Windows DNS servers it
    # enumerates the special TrustAnchors scope and can fail even though normal DNS
    # administration is healthy. Query the zone list instead; TrustAnchors is excluded
    # later from all aging/scavenging operations.
    $healthZones = @(Get-DnsServerZone -ComputerName $ScavengingServer -ErrorAction Stop)
    if ($healthZones.Count -lt 1) { throw "The DNS server returned no zones." }
    Write-RITLog -Level PASS -Message "DNS server '$ScavengingServer' is reachable through the DnsServer module; $($healthZones.Count) zone(s) returned."
} catch {
    Add-RITError "Unable to query DNS zones on server '$ScavengingServer': $($_.Exception.Message)"
    exit $Script:ExitCode
}

$noRefresh = New-TimeSpan -Days $NoRefreshDays
$refresh = New-TimeSpan -Days $RefreshDays
$scavengeInterval = New-TimeSpan -Days $ScavengingIntervalDays

try {
    $serverBefore = Get-DnsServerScavenging -ComputerName $ScavengingServer -ErrorAction Stop
    Write-RITLog "Current server scavenging state: ScavengingState=$($serverBefore.ScavengingState); ScavengingInterval=$($serverBefore.ScavengingInterval)."
} catch {
    Add-RITError "Could not read server scavenging configuration: $($_.Exception.Message)"
    $serverBefore = $null
}

try {
    $zones = @(Get-RITEligibleZones -Server $ScavengingServer)
    if ($zones.Count -eq 0) { throw 'No eligible AD-integrated primary DNS zones were found.' }
    Write-RITLog -Level PASS -Message ("Eligible zones: {0}" -f (($zones | Select-Object -ExpandProperty ZoneName) -join ', '))
} catch {
    Add-RITError "Zone discovery failed: $($_.Exception.Message)"
    exit $Script:ExitCode
}

$zoneBefore = @()
foreach ($zone in $zones) {
    try {
        $aging = Get-DnsServerZoneAging -ComputerName $ScavengingServer -Name $zone.ZoneName -ErrorAction Stop
        $zoneBefore += [pscustomobject]@{
            Zone = $zone.ZoneName
            IsReverseLookupZone = $zone.IsReverseLookupZone
            AgingEnabledBefore = $aging.AgingEnabled
            NoRefreshBefore = $aging.NoRefreshInterval
            RefreshBefore = $aging.RefreshInterval
            AvailForScavengeTimeBefore = $aging.AvailForScavengeTime
            AgingEnabledAfter = $null
            NoRefreshAfter = $null
            RefreshAfter = $null
            AvailForScavengeTimeAfter = $null
        }
        Write-RITLog "Zone '$($zone.ZoneName)': AgingEnabled=$($aging.AgingEnabled); NoRefresh=$($aging.NoRefreshInterval); Refresh=$($aging.RefreshInterval); AvailableForScavenge=$($aging.AvailForScavengeTime)."
    } catch {
        Add-RITError "Could not read aging settings for '$($zone.ZoneName)': $($_.Exception.Message)"
    }
}

$before = @(Get-RITRecordInventory -Server $ScavengingServer -Zones $zones -NoRefresh $noRefresh -Refresh $refresh)
$before | Export-Csv -LiteralPath $Script:BeforeCsv -NoTypeInformation -Encoding UTF8
$staleBefore = @($before | Where-Object { $_.StaleCandidateByAge -eq $true -and $_.IsStatic -eq $false })
$staleBefore | Export-Csv -LiteralPath $Script:StaleCsv -NoTypeInformation -Encoding UTF8
Write-RITLog -Level PASS -Message "Before inventory exported: $($before.Count) records; $($staleBefore.Count) dynamic records meet the calculated age threshold."
Write-RITLog -Level WARN -Message 'A stale-candidate calculation indicates age only. Actual deletion remains controlled by Windows DNS aging/scavenging eligibility and zone timers.'

if (-not $AuditOnly) {
    try {
        if ($PSCmdlet.ShouldProcess($ScavengingServer,"Enable DNS server scavenging with interval $ScavengingIntervalDays days")) {
            Set-DnsServerScavenging -ComputerName $ScavengingServer -ScavengingState $true -ScavengingInterval $scavengeInterval -ApplyOnAllZones:$false -PassThru -ErrorAction Stop | Out-Null
            $Script:Changes += "Enabled server scavenging on $ScavengingServer with $ScavengingIntervalDays-day interval."
            Write-RITLog -Level CHANGE -Message "Enabled DNS server scavenging with a $ScavengingIntervalDays-day interval."
        }
    } catch {
        Add-RITError "Failed to configure DNS server scavenging: $($_.Exception.Message)"
    }

    foreach ($zone in $zones) {
        try {
            if ($PSCmdlet.ShouldProcess($zone.ZoneName,"Enable aging; NoRefresh=$NoRefreshDays days; Refresh=$RefreshDays days")) {
                Set-DnsServerZoneAging -ComputerName $ScavengingServer -Name $zone.ZoneName -Aging $true -NoRefreshInterval $noRefresh -RefreshInterval $refresh -PassThru -ErrorAction Stop | Out-Null
                $Script:Changes += "Configured aging on $($zone.ZoneName): NoRefresh=$NoRefreshDays days; Refresh=$RefreshDays days."
                Write-RITLog -Level CHANGE -Message "Configured aging for '$($zone.ZoneName)' with NoRefresh=$NoRefreshDays days and Refresh=$RefreshDays days."
            }
        } catch {
            Add-RITError "Failed to configure zone aging for '$($zone.ZoneName)': $($_.Exception.Message)"
        }
    }

    try {
        if ($PSCmdlet.ShouldProcess($ScavengingServer,'Start DNS scavenging')) {
            Write-RITLog 'Requesting an immediate supported DNS scavenging pass.'
            Start-DnsServerScavenging -ComputerName $ScavengingServer -Verbose -ErrorAction Stop 4>&1 | ForEach-Object { Write-RITLog ([string]$_) }
            $Script:Changes += "Requested immediate DNS scavenging on $ScavengingServer."
            Write-RITLog -Level PASS -Message 'DNS scavenging request completed. Zone protection/scavenge-after timers may prevent immediate removal of newly eligible records.'
        }
    } catch {
        Add-RITError "DNS scavenging request failed: $($_.Exception.Message)"
    }
}

$serverAfter = $null
try { $serverAfter = Get-DnsServerScavenging -ComputerName $ScavengingServer -ErrorAction Stop } catch { Add-RITError "Could not read post-change server scavenging configuration: $($_.Exception.Message)" }

foreach ($row in $zoneBefore) {
    try {
        $aging = Get-DnsServerZoneAging -ComputerName $ScavengingServer -Name $row.Zone -ErrorAction Stop
        $row.AgingEnabledAfter = $aging.AgingEnabled
        $row.NoRefreshAfter = $aging.NoRefreshInterval
        $row.RefreshAfter = $aging.RefreshInterval
        $row.AvailForScavengeTimeAfter = $aging.AvailForScavengeTime
    } catch {
        Add-RITError "Could not verify post-change aging settings for '$($row.Zone)': $($_.Exception.Message)"
    }
}
$zoneBefore | Export-Csv -LiteralPath $Script:ZoneCsv -NoTypeInformation -Encoding UTF8

$after = @(Get-RITRecordInventory -Server $ScavengingServer -Zones $zones -NoRefresh $noRefresh -Refresh $refresh)
$after | Export-Csv -LiteralPath $Script:AfterCsv -NoTypeInformation -Encoding UTF8

$beforeKeys = @{}
foreach ($r in $before) { $beforeKeys["$($r.Zone)|$($r.HostName)|$($r.RecordType)|$($r.RecordData)"] = $true }
$afterKeys = @{}
foreach ($r in $after) { $afterKeys["$($r.Zone)|$($r.HostName)|$($r.RecordType)|$($r.RecordData)"] = $true }
$removedCount = @($beforeKeys.Keys | Where-Object { -not $afterKeys.ContainsKey($_) }).Count

$summary = [ordered]@{
    ScriptVersion = '1.0.1'
    ComputerName = $Script:ComputerName
    ScavengingServer = $ScavengingServer
    AuditOnly = [bool]$AuditOnly
    Started = $Script:StartTime
    Completed = Get-Date
    Settings = [ordered]@{
        NoRefreshDays = $NoRefreshDays
        RefreshDays = $RefreshDays
        ScavengingIntervalDays = $ScavengingIntervalDays
    }
    ServerBefore = if ($serverBefore) { [ordered]@{ ScavengingState=$serverBefore.ScavengingState; ScavengingInterval=[string]$serverBefore.ScavengingInterval } } else { $null }
    ServerAfter = if ($serverAfter) { [ordered]@{ ScavengingState=$serverAfter.ScavengingState; ScavengingInterval=[string]$serverAfter.ScavengingInterval } } else { $null }
    ZonesProcessed = @($zones | Select-Object -ExpandProperty ZoneName)
    RecordCountBefore = $before.Count
    CalculatedStaleCandidatesBefore = $staleBefore.Count
    RecordCountAfter = $after.Count
    RecordsNoLongerPresentAfterRun = $removedCount
    Changes = @($Script:Changes)
    Errors = @($Script:Errors)
    Files = [ordered]@{
        Log = $Script:LogFile
        BeforeInventory = $Script:BeforeCsv
        StaleCandidates = $Script:StaleCsv
        AfterInventory = $Script:AfterCsv
        ZoneAging = $Script:ZoneCsv
    }
    ExitCode = $Script:ExitCode
}
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Script:SummaryJson -Encoding UTF8

Write-RITLog '---------------- DNS Aging/Scavenging Summary ----------------'
Write-RITLog "DNS server: $ScavengingServer"
Write-RITLog "Zones processed: $($zones.Count)"
Write-RITLog "Records before: $($before.Count)"
Write-RITLog "Calculated stale dynamic candidates before: $($staleBefore.Count)"
Write-RITLog "Records after: $($after.Count)"
Write-RITLog "Records no longer present after run: $removedCount"
if ($serverAfter) { Write-RITLog "Server scavenging after: State=$($serverAfter.ScavengingState); Interval=$($serverAfter.ScavengingInterval)" }
Write-RITLog "Zone report: $Script:ZoneCsv"
Write-RITLog "Stale candidate report: $Script:StaleCsv"
Write-RITLog "Summary JSON: $Script:SummaryJson"
if ($Script:Errors.Count -gt 0) {
    Write-RITLog -Level WARN -Message "Completed with $($Script:Errors.Count) error(s). Exit code $Script:ExitCode."
} else {
    Write-RITLog -Level PASS -Message 'Completed successfully. Exit code 0.'
}
exit $Script:ExitCode
