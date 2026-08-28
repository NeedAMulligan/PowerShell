#requires -Version 5.1

<#
.SYNOPSIS
    Exports SentinelOne device usage totals by account and site.

.DESCRIPTION
    Queries the SentinelOne Management Console API and creates:
      1. A client/site usage summary CSV.
      2. A detailed endpoint inventory CSV.
      3. A timestamped execution log.

    The script performs read-only API calls. The API token is supplied at run
    time or through a process-scoped environment variable.

.PARAMETER ConsoleUrl
    SentinelOne console URL, for example https://usea1-000.sentinelone.net

.PARAMETER ApiToken
    SentinelOne API token. If omitted, the script checks the S1_API_TOKEN
    environment variable and then prompts securely.

.PARAMETER OutputDirectory
    Destination for CSV and log files. Defaults to C:\Temp.

.PARAMETER InactiveDays
    Number of days without communication before an endpoint is classified as
    inactive. Defaults to 30 days.

.EXAMPLE
    .\Export-SentinelOneClientUsage-v1.0.0.ps1 `
        -ConsoleUrl "https://usea1-000.sentinelone.net"

.EXAMPLE
    $env:S1_API_TOKEN = "your-token"
    .\Export-SentinelOneClientUsage-v1.0.0.ps1 `
        -ConsoleUrl "https://usea1-000.sentinelone.net" `
        -InactiveDays 30

.NOTES
    Required SentinelOne permission: Endpoints.view
    API endpoint used: GET /web/api/v2.1/agents
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^https://')]
    [string]$ConsoleUrl,

    [Parameter()]
    [string]$ApiToken,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputDirectory = 'C:\Temp',

    [Parameter()]
    [ValidateRange(1, 3650)]
    [int]$InactiveDays = 30
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$script:LogPath = $null

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Message,
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS')] [string]$Level = 'INFO'
    )

    $entry = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $entry
    if ($script:LogPath) {
        Add-Content -LiteralPath $script:LogPath -Value $entry -Encoding UTF8
    }
}

function ConvertFrom-SecureToken {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [Security.SecureString]$SecureToken)

    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureToken)
    try {
        [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function Invoke-SentinelOneGet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Uri,
        [Parameter(Mandatory)] [hashtable]$Headers
    )

    try {
        Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers -ContentType 'application/json'
    }
    catch {
        $statusCode = $null
        if ($_.Exception.Response) {
            try { $statusCode = [int]$_.Exception.Response.StatusCode } catch { }
        }

        $detail = if ($statusCode) { "HTTP $statusCode" } else { $_.Exception.Message }
        throw "SentinelOne API request failed ($detail): $Uri"
    }
}

function Get-SentinelOneAgents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$BaseUrl,
        [Parameter(Mandatory)] [hashtable]$Headers
    )

    $results = [Collections.Generic.List[object]]::new()
    $cursor = $null
    $page = 0

    do {
        $page++
        $query = [Collections.Generic.List[string]]::new()
        $query.Add('limit=1000')
        $query.Add('sortBy=computerName')
        $query.Add('sortOrder=asc')
        if ($cursor) {
            $query.Add('cursor=' + [uri]::EscapeDataString([string]$cursor))
        }

        $uri = '{0}/web/api/v2.1/agents?{1}' -f $BaseUrl, ($query -join '&')
        Write-Log "Retrieving endpoint page $page..."
        $response = Invoke-SentinelOneGet -Uri $uri -Headers $Headers

        foreach ($agent in @($response.data)) {
            $results.Add($agent)
        }

        $cursor = $response.pagination.nextCursor
    } while ($cursor)

    return $results
}

try {
    if (-not (Test-Path -LiteralPath $OutputDirectory)) {
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:LogPath = Join-Path $OutputDirectory "SentinelOne-Usage-$timestamp.log"
    $summaryPath = Join-Path $OutputDirectory "SentinelOne-ClientUsage-Summary-$timestamp.csv"
    $detailPath = Join-Path $OutputDirectory "SentinelOne-EndpointInventory-$timestamp.csv"

    Write-Log 'Starting SentinelOne client usage export.'

    $ConsoleUrl = $ConsoleUrl.Trim().TrimEnd('/')
    if (-not $ApiToken) {
        $ApiToken = [Environment]::GetEnvironmentVariable('S1_API_TOKEN', 'Process')
    }
    if (-not $ApiToken) {
        $secureToken = Read-Host 'Enter the SentinelOne API token' -AsSecureString
        $ApiToken = ConvertFrom-SecureToken -SecureToken $secureToken
    }
    if ([string]::IsNullOrWhiteSpace($ApiToken)) {
        throw 'A SentinelOne API token was not supplied.'
    }

    $headers = @{
        Authorization = "ApiToken $ApiToken"
        Accept        = 'application/json'
    }

    $agents = @(Get-SentinelOneAgents -BaseUrl $ConsoleUrl -Headers $headers)
    Write-Log "Retrieved $($agents.Count) endpoint records."

    $now = Get-Date
    $inactiveCutoff = $now.AddDays(-$InactiveDays)

    $details = foreach ($agent in $agents) {
        $lastActive = $null
        if ($agent.lastActiveDate) {
            try { $lastActive = [datetime]$agent.lastActiveDate } catch { }
        }

        $isDecommissioned = [bool]$agent.isDecommissioned
        $isInactive = (-not $isDecommissioned) -and (($null -eq $lastActive) -or ($lastActive -lt $inactiveCutoff))
        $isActive = (-not $isDecommissioned) -and (-not $isInactive)
        $networkStatus = [string]$agent.networkStatus
        $isDisconnected = (-not $isDecommissioned) -and ($networkStatus -notmatch 'connected')

        [pscustomobject]@{
            ReportDate       = $now.ToString('yyyy-MM-dd')
            AccountName      = $agent.accountName
            AccountId        = $agent.accountId
            SiteName         = $agent.siteName
            SiteId           = $agent.siteId
            ComputerName     = $agent.computerName
            AgentId          = $agent.id
            AgentVersion     = $agent.agentVersion
            OperatingSystem  = $agent.osName
            MachineType      = $agent.machineType
            NetworkStatus    = $networkStatus
            LastActiveDate   = if ($lastActive) { $lastActive.ToString('yyyy-MM-dd HH:mm:ss') } else { $null }
            Active           = $isActive
            Inactive         = $isInactive
            Disconnected     = $isDisconnected
            Decommissioned   = $isDecommissioned
            Infected         = [bool]$agent.infected
            IsUninstalled    = [bool]$agent.isUninstalled
            InactiveDaysRule = $InactiveDays
        }
    }

    $summary = foreach ($group in ($details | Group-Object AccountId, SiteId)) {
        $rows = @($group.Group)
        $billableRows = @($rows | Where-Object { -not $_.Decommissioned -and -not $_.IsUninstalled })

        [pscustomobject]@{
            ReportDate          = $now.ToString('yyyy-MM-dd')
            AccountName         = $rows[0].AccountName
            AccountId           = $rows[0].AccountId
            SiteName            = $rows[0].SiteName
            SiteId              = $rows[0].SiteId
            BillableDeviceCount = $billableRows.Count
            ActiveDevices       = @($billableRows | Where-Object Active).Count
            InactiveDevices     = @($billableRows | Where-Object Inactive).Count
            DisconnectedDevices = @($billableRows | Where-Object Disconnected).Count
            InfectedDevices     = @($billableRows | Where-Object Infected).Count
            Decommissioned      = @($rows | Where-Object Decommissioned).Count
            Uninstalled         = @($rows | Where-Object IsUninstalled).Count
            TotalApiRecords     = $rows.Count
            InactiveDaysRule    = $InactiveDays
        }
    }

    $details | Sort-Object AccountName, SiteName, ComputerName |
        Export-Csv -LiteralPath $detailPath -NoTypeInformation -Encoding UTF8
    $summary | Sort-Object AccountName, SiteName |
        Export-Csv -LiteralPath $summaryPath -NoTypeInformation -Encoding UTF8

    Write-Log "Summary exported to $summaryPath" -Level SUCCESS
    Write-Log "Endpoint inventory exported to $detailPath" -Level SUCCESS
    Write-Log 'SentinelOne client usage export completed.' -Level SUCCESS

    [pscustomobject]@{
        SummaryCsv   = $summaryPath
        DetailCsv    = $detailPath
        LogFile      = $script:LogPath
        ApiRecords   = $agents.Count
        ClientSites  = @($summary).Count
        BillableTotal = ($summary | Measure-Object -Property BillableDeviceCount -Sum).Sum
    }
}
catch {
    Write-Log $_.Exception.Message -Level ERROR
    throw
}
finally {
    $ApiToken = $null
    $headers = $null
}
