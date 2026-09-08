#Requires -Version 5.1
<#
.SYNOPSIS
    Captures NIC MAC addresses on the local Windows computer.
.DESCRIPTION
    Inventories adapters returned by Get-NetAdapter -IncludeHidden, without
    filtering by connection state. Missing MACs are checked against raw CIM
    NetworkAddresses, Win32_NetworkAdapter, Win32_NetworkAdapterConfiguration,
    and .NET NetworkInterface.GetPhysicalAddress().

    Fallback records are matched by interface GUID first, or by a unique,
    positive interface index when no conflicting GUID exists. They are never
    matched by list position, similar description, or MAC address.

    Writes timestamped CSV, JSON, diagnostic JSON, and an activity log. Raw
    provider values are retained in the diagnostic JSON. A permanent address
    is never substituted for an unknown current address, or vice versa.

    Read-only network inventory: no adapter resets, service restarts, registry
    changes, module installations, network configuration changes, or prompts.
.PARAMETER OutputDirectory
    Output folder. Default: C:\Temp. OutputPath is a compatible alias.
.PARAMETER PhysicalOnly
    Requests only adapters Get-NetAdapter identifies as physical.
.PARAMETER PassThru
    Also returns inventory records as PowerShell objects.
.EXAMPLE
    .\Export-NICMacAddresses-v1.0.1.ps1
.EXAMPLE
    .\Export-NICMacAddresses-v1.0.1.ps1 -PhysicalOnly
.EXAMPLE
    .\Export-NICMacAddresses-v1.0.1.ps1 -OutputPath 'C:\Temp\NIC-Inventory'
.NOTES
    Author: Resilient IT
    Version: 1.0.1
    Requires: Windows PowerShell 5.1+ and the Windows NetAdapter module.
    Run locally with rights to query adapters and write the output directory.
    Designed for an interactive console or an authorized RMM/SYSTEM session.

    Some virtual or unavailable adapters may not report an address. This is
    not a historical inventory of removed devices, and it does not discover
    a server's out-of-band iLO, iDRAC, or BMC interfaces. Permanent addresses
    are driver-reported values, not an independent hardware verification.

    v1.0.1: Adds raw-property reads, alternate MAC providers, GUID-safe matching,
    per-source diagnostics, and explicit warnings for missing physical MACs.
    Helper functions use a RITNIC prefix to avoid generic-name collisions.
.LINK
    https://learn.microsoft.com/powershell/module/netadapter/get-netadapter
.LINK
    https://learn.microsoft.com/windows/win32/fwp/wmi/netadaptercimprov/msft-netadapter
.LINK
    https://learn.microsoft.com/windows/win32/cimwin32prov/win32-networkadapter
.LINK
    https://learn.microsoft.com/windows/win32/cimwin32prov/win32-networkadapterconfiguration
.LINK
    https://learn.microsoft.com/dotnet/api/system.net.networkinformation.networkinterface.getphysicaladdress
#>
[CmdletBinding()]
param (
    [Alias('OutputPath')]
    [ValidateNotNullOrEmpty()]
    [string]$OutputDirectory = 'C:\Temp',
    [switch]$PhysicalOnly,
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
$script:RITNICLogPath = $null
$scriptVersion = '1.0.1'

function Write-RITNICLog {
    param (
        [string]$Message,
        [ValidateSet('INFO','SUCCESS','WARNING','ERROR')][string]$Level = 'INFO'
    )
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
    if ($script:RITNICLogPath) {
        try { Add-Content -LiteralPath $script:RITNICLogPath -Value $line -Encoding UTF8 -ErrorAction Stop }
        catch { Write-Warning ('Could not append to the activity log: {0}' -f $_.Exception.Message) -WarningAction Continue }
    }
}

function Get-RITNICValue {
    param ([AllowNull()][object]$Object, [string]$Name, [switch]$Raw)
    if ($null -eq $Object) { return $null }
    try {
        if ($Raw) {
            # Bypass extended/script properties when reading underlying CIM data.
            $collection = $Object.PSObject.Properties['CimInstanceProperties']
            if ($null -ne $collection) {
                $property = $collection.Value[$Name]
                if ($null -ne $property) { return $property.Value }
            }
            return $null
        }
        $property = $Object.PSObject.Properties[$Name]
        if ($null -ne $property) { return $property.Value }
    }
    catch {
        Write-RITNICLog -Level WARNING -Message ('Property read failed ({0}): {1}' -f $Name, $_.Exception.Message)
    }
    return $null
}

function ConvertTo-RITNICMac {
    param ([AllowNull()][object]$Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [byte[]]) { $text = [BitConverter]::ToString($Value) }
    else { $text = ([string]$Value).Trim().ToUpperInvariant() }
    $compact = $text -replace '[-:.\s]', ''
    # Preserve longer link-layer addresses, but reject empty/zero/broadcast data.
    if ($compact -notmatch '^(?:[0-9A-F]{2}){6,32}$') { return '' }
    if ($compact -match '^0+$' -or $compact -match '^F+$') { return '' }
    return ($compact -replace '(.{2})(?=.)', '$1-')
}

function ConvertTo-RITNICGuid {
    param ([AllowNull()][object]$Value)
    $parsed = [Guid]::Empty
    if ([Guid]::TryParse([string]$Value, [ref]$parsed) -and $parsed -ne [Guid]::Empty) {
        return $parsed.ToString('D').ToUpperInvariant()
    }
    return ''
}

function Find-RITNICRecord {
    param (
        [AllowEmptyCollection()][object[]]$Records,
        [string]$Guid,
        [AllowNull()][object]$Index,
        [string]$GuidProperty
    )
    if ($Guid) {
        $matchesByGuid = @($Records | Where-Object {
            (ConvertTo-RITNICGuid (Get-RITNICValue $_ $GuidProperty)) -eq $Guid
        })
        if ($matchesByGuid.Count -eq 1) { return $matchesByGuid[0] }
        if ($matchesByGuid.Count -gt 1) { return $null }
    }
    if ($null -ne $Index -and [long]$Index -gt 0) {
        $matchesByIndex = @($Records | Where-Object {
            $otherIndex = Get-RITNICValue $_ 'InterfaceIndex'
            $otherGuid = ConvertTo-RITNICGuid (Get-RITNICValue $_ $GuidProperty)
            ($null -ne $otherIndex) -and ([string]$otherIndex -eq [string]$Index) -and
            (-not $Guid -or -not $otherGuid -or $Guid -eq $otherGuid)
        })
        if ($matchesByIndex.Count -eq 1) { return $matchesByIndex[0] }
    }
    return $null
}

function Get-RITNICDotNetRecords {
    foreach ($nic in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
        $index = $null
        $address = ''
        try { $index = $nic.GetIPProperties().GetIPv4Properties().Index } catch { }
        if ($null -eq $index) {
            try { $index = $nic.GetIPProperties().GetIPv6Properties().Index } catch { }
        }
        try { $address = $nic.GetPhysicalAddress().ToString() }
        catch { Write-RITNICLog -Level WARNING -Message ('.NET address read failed for {0}: {1}' -f $nic.Name, $_.Exception.Message) }
        [PSCustomObject]@{
            Id = $nic.Id
            InterfaceIndex = $index
            MACAddress = $address
            Name = $nic.Name
        }
    }
}

try {
    if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
        New-Item -Path $OutputDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
    $OutputDirectory = (Get-Item -LiteralPath $OutputDirectory -ErrorAction Stop).FullName
    $computerName = [Environment]::MachineName
    if ($env:COMPUTERNAME) { $computerName = $env:COMPUTERNAME }
    $collectedAt = [DateTimeOffset]::Now
    $prefix = 'NIC-MAC_{0}_{1}' -f $computerName, $collectedAt.ToString('yyyyMMdd_HHmmss_fff')
    $csvPath = Join-Path $OutputDirectory ($prefix + '.csv')
    $jsonPath = Join-Path $OutputDirectory ($prefix + '.json')
    $diagnosticPath = Join-Path $OutputDirectory ($prefix + '_Diagnostics.json')
    $script:RITNICLogPath = Join-Path $OutputDirectory ($prefix + '.log')
    Write-RITNICLog ('Starting NIC MAC address inventory v{0} on {1}.' -f $scriptVersion, $computerName)

    if (-not (Get-Command Get-NetAdapter -ErrorAction SilentlyContinue)) {
        throw 'Get-NetAdapter is unavailable. Run in Windows PowerShell with the Windows NetAdapter module.'
    }
    $parameters = @{ Name = '*'; IncludeHidden = $true; ErrorAction = 'Stop' }
    if ($PhysicalOnly) { $parameters['Physical'] = $true }
    $adapters = @(Get-NetAdapter @parameters | Sort-Object Name, InterfaceIndex)
    if ($adapters.Count -eq 0) { throw 'No network adapters were returned for the selected scope.' }
    Write-RITNICLog ('Found {0} adapter(s). PhysicalOnly={1}. No connection-state filter is applied.' -f $adapters.Count, [bool]$PhysicalOnly)

    # Legacy WMI classes are compatibility fallbacks, not the primary inventory.
    # Each provider is queried once; one failed fallback does not stop capture.
    $providers = @{}
    $providerStatus = [ordered]@{ GetNetAdapter = 'Succeeded' }
    foreach ($className in @('Win32_NetworkAdapter', 'Win32_NetworkAdapterConfiguration')) {
        try {
            $providers[$className] = @(Get-CimInstance -Namespace 'root\cimv2' -ClassName $className -OperationTimeoutSec 30 -ErrorAction Stop)
            $providerStatus[$className] = 'Succeeded: {0} record(s)' -f $providers[$className].Count
            Write-RITNICLog ('{0}: {1} record(s).' -f $className, $providers[$className].Count)
        }
        catch {
            $providers[$className] = @()
            $providerStatus[$className] = 'Failed: {0}' -f $_.Exception.Message
            Write-RITNICLog -Level WARNING -Message ('{0} unavailable; continuing. {1}' -f $className, $_.Exception.Message)
        }
    }
    try {
        $dotNetRecords = @(Get-RITNICDotNetRecords)
        $providerStatus['DotNet'] = 'Succeeded: {0} record(s)' -f $dotNetRecords.Count
    }
    catch {
        $dotNetRecords = @()
        $providerStatus['DotNet'] = 'Failed: {0}' -f $_.Exception.Message
        Write-RITNICLog -Level WARNING -Message ('.NET fallback unavailable; continuing. {0}' -f $_.Exception.Message)
    }

    $diagnostics = [System.Collections.Generic.List[object]]::new()
    $results = @(
        foreach ($adapter in $adapters) {
            $guid = ConvertTo-RITNICGuid (Get-RITNICValue $adapter 'InterfaceGuid')
            $index = Get-RITNICValue $adapter 'InterfaceIndex'
            $legacy = Find-RITNICRecord -Records $providers['Win32_NetworkAdapter'] -Guid $guid -Index $index -GuidProperty 'GUID'
            $config = Find-RITNICRecord -Records $providers['Win32_NetworkAdapterConfiguration'] -Guid $guid -Index $index -GuidProperty 'SettingID'
            $dotNet = Find-RITNICRecord -Records $dotNetRecords -Guid $guid -Index $index -GuidProperty 'Id'

            $directMac = Get-RITNICValue $adapter 'MacAddress'
            $rawNetworkAddresses = @(Get-RITNICValue $adapter 'NetworkAddresses' -Raw | Where-Object { $null -ne $_ })
            if ($rawNetworkAddresses.Count -eq 0) {
                $rawNetworkAddresses = @(Get-RITNICValue $adapter 'NetworkAddresses' | Where-Object { $null -ne $_ })
            }
            $networkMacs = @($rawNetworkAddresses | ForEach-Object { ConvertTo-RITNICMac $_ } | Where-Object { $_ } | Select-Object -Unique)
            $singleNetworkMac = ''
            if ($networkMacs.Count -eq 1) { $singleNetworkMac = $networkMacs[0] }

            $legacyMac = Get-RITNICValue $legacy 'MACAddress'
            $configMac = Get-RITNICValue $config 'MACAddress'
            $dotNetMac = Get-RITNICValue $dotNet 'MACAddress'
            $candidates = @(
                [PSCustomObject]@{ Value = $directMac; Source = 'Get-NetAdapter.MacAddress' }
                [PSCustomObject]@{ Value = $singleNetworkMac; Source = 'Get-NetAdapter.NetworkAddresses' }
                [PSCustomObject]@{ Value = $legacyMac; Source = 'Win32_NetworkAdapter.MACAddress' }
                [PSCustomObject]@{ Value = $configMac; Source = 'Win32_NetworkAdapterConfiguration.MACAddress' }
                [PSCustomObject]@{ Value = $dotNetMac; Source = '.NET.GetPhysicalAddress' }
            )
            $mac = ''
            $macSource = 'Not reported'
            $usableValues = @()
            foreach ($candidate in $candidates) {
                $value = ConvertTo-RITNICMac $candidate.Value
                if ($value) {
                    $usableValues += $value
                    if (-not $mac) { $mac = $value; $macSource = $candidate.Source }
                }
            }
            $conflict = @($usableValues | Select-Object -Unique).Count -gt 1
            $state = 'Not reported by available sources'
            if ($mac) {
                $state = 'Reported'
                if ($mac.Length -ne 17) { $state = 'Reported - non-48-bit address' }
                if ($conflict) { $state = 'Reported - sources differ; review diagnostics' }
            }

            # Raw CIM avoids relying exclusively on extended PermanentAddress.
            $rawPermanent = Get-RITNICValue $adapter 'PermanentAddress' -Raw
            $directPermanent = Get-RITNICValue $adapter 'PermanentAddress'
            $permanent = ConvertTo-RITNICMac $rawPermanent
            $permanentSource = 'Not reported'
            if ($permanent) { $permanentSource = 'Get-NetAdapter.PermanentAddress (raw CIM)' }
            if (-not $permanent) {
                $permanent = ConvertTo-RITNICMac $directPermanent
                if ($permanent) { $permanentSource = 'Get-NetAdapter.PermanentAddress' }
            }

            $diagnostics.Add([PSCustomObject][ordered]@{
                AdapterName = [string]$adapter.Name
                InterfaceGuid = $guid
                InterfaceIndex = $index
                GetNetAdapterMAC = $directMac
                NetworkAddresses = @($rawNetworkAddresses)
                RawPermanentAddress = $rawPermanent
                ExposedPermanentAddress = $directPermanent
                Win32AdapterMatched = ($null -ne $legacy)
                Win32AdapterMAC = $legacyMac
                Win32ConfigurationMatched = ($null -ne $config)
                Win32ConfigurationMAC = $configMac
                DotNetMatched = ($null -ne $dotNet)
                DotNetMAC = $dotNetMac
                SourceConflict = $conflict
            })
            [PSCustomObject][ordered]@{
                ComputerName = $computerName
                CollectedAt = $collectedAt.ToString('o')
                AdapterName = [string]$adapter.Name
                InterfaceDescription = [string]$adapter.InterfaceDescription
                InterfaceIndex = $index
                MACAddress = $mac
                PermanentMACAddress = $permanent
                MACAddressState = $state
                Status = [string]$adapter.Status
                LinkSpeed = [string]$adapter.LinkSpeed
                PhysicalAdapter = $adapter.HardwareInterface
                VirtualAdapter = $adapter.Virtual
                HiddenAdapter = $adapter.Hidden
                InterfaceGuid = $guid
                MACAddressSource = $macSource
                PermanentMACAddressSource = $permanentSource
                SourceConflict = $conflict
            }
        }
    )

    $results | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8 -NoClobber -ErrorAction Stop
    ConvertTo-Json -InputObject @($results) -Depth 5 | Set-Content -LiteralPath $jsonPath -Encoding UTF8 -ErrorAction Stop
    $diagnosticReport = [ordered]@{
        ScriptVersion = $scriptVersion
        ComputerName = $computerName
        CollectedAt = $collectedAt.ToString('o')
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        Providers = $providerStatus
        Adapters = $diagnostics.ToArray()
    }
    ConvertTo-Json -InputObject $diagnosticReport -Depth 7 | Set-Content -LiteralPath $diagnosticPath -Encoding UTF8 -ErrorAction Stop

    Write-Host ''
    $results | Format-Table AdapterName, MACAddress, Status, PhysicalAdapter, MACAddressSource -AutoSize |
        Out-String -Width 260 | Write-Host
    $reported = @($results | Where-Object { $_.MACAddress }).Count
    $missingPhysical = @($results | Where-Object { $_.PhysicalAdapter -eq $true -and -not $_.MACAddress })
    $conflicts = @($results | Where-Object { $_.SourceConflict })
    Write-RITNICLog ('Captured {0} adapter(s); {1} have a current address; {2} do not.' -f $results.Count, $reported, ($results.Count - $reported))
    foreach ($row in $missingPhysical) {
        Write-RITNICLog -Level WARNING -Message ('Physical NIC "{0}" ({1}) still has no current MAC. Review the diagnostic JSON.' -f $row.AdapterName, $row.Status)
    }
    if ($conflicts.Count -gt 0) {
        Write-RITNICLog -Level WARNING -Message ('{0} adapter(s) have differing provider values; review diagnostics before using these addresses.' -f $conflicts.Count)
    }
    if ($reported -eq 0) {
        Write-RITNICLog -Level WARNING -Message 'No current MAC addresses were captured. The inventory is not a successful MAC-address collection.'
    }
    elseif ($missingPhysical.Count -eq 0 -and $conflicts.Count -eq 0) {
        Write-RITNICLog -Level SUCCESS -Message 'Address capture finished. Some virtual/unavailable interfaces may have no reported address.'
    }
    Write-RITNICLog ('CSV report: {0}' -f $csvPath)
    Write-RITNICLog ('JSON report: {0}' -f $jsonPath)
    Write-RITNICLog ('Diagnostics: {0}' -f $diagnosticPath)
    Write-RITNICLog ('Activity log: {0}' -f $script:RITNICLogPath)
    if ($PassThru) { $results }
}
catch {
    Write-RITNICLog -Level ERROR -Message ('Inventory failed: {0}' -f $_.Exception.Message)
    throw
}
