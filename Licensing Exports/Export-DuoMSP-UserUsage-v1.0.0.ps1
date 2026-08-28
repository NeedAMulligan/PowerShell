#requires -Version 5.1

<#
.SYNOPSIS
    Exports Duo MSP user inventory and usage counts by subaccount.

.DESCRIPTION
    Uses a parent-account Duo Admin API integration with subaccount permissions.
    Implements Duo v5 HMAC-SHA512 request signing, retrieves all MSP subaccounts,
    pages through all users, retrieves each subaccount edition, and exports a
    client summary plus detailed user inventory.

    The secret key is requested securely and is never written to a report or log.

.PARAMETER ApiHostname
    Parent Duo Admin API hostname, such as api-xxxxxxxx.duosecurity.com.

.PARAMETER IntegrationKey
    Integration key for the parent-account Admin API application.

.PARAMETER SecretKey
    Optional secret key. If omitted, the script prompts securely.

.PARAMETER OutputDirectory
    Report destination. Defaults to C:\Temp.

.EXAMPLE
    .\Export-DuoMSP-UserUsage-v1.0.0.ps1 `
        -ApiHostname 'api-xxxxxxxx.duosecurity.com' `
        -IntegrationKey 'DIXXXXXXXXXXXXXXXXXX'

.NOTES
    Required parent integration permissions:
      - Grant resource - Read
      - Admin API subaccount permissions

    Read-only endpoints:
      POST /accounts/v1/account/list
      GET  /admin/v1/users
      GET  /admin/v1/billing/edition
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^api-[A-Za-z0-9.-]+\.duosecurity\.com$')]
    [string]$ApiHostname,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$IntegrationKey,

    [Parameter()]
    [string]$SecretKey,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputDirectory = 'C:\Temp'
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

function ConvertFrom-SecureValue {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [Security.SecureString]$SecureValue)

    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
    try {
        [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function Get-Sha512Hex {
    [CmdletBinding()]
    param([AllowEmptyString()] [string]$Value = '')

    $algorithm = [Security.Cryptography.SHA512]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
        $hash = $algorithm.ComputeHash($bytes)
        return -join ($hash | ForEach-Object { $_.ToString('x2') })
    }
    finally {
        $algorithm.Dispose()
    }
}

function ConvertTo-DuoEncodedValue {
    [CmdletBinding()]
    param([AllowEmptyString()] [string]$Value)

    return [uri]::EscapeDataString($Value).Replace('%7e', '~').Replace('%7E', '~')
}

function ConvertTo-DuoQueryString {
    [CmdletBinding()]
    param([hashtable]$Parameters)

    if (-not $Parameters -or $Parameters.Count -eq 0) {
        return ''
    }

    $parts = foreach ($key in ($Parameters.Keys | Sort-Object)) {
        $value = [string]$Parameters[$key]
        '{0}={1}' -f (ConvertTo-DuoEncodedValue ([string]$key)), (ConvertTo-DuoEncodedValue $value)
    }
    return $parts -join '&'
}

function New-DuoV5Headers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Method,
        [Parameter(Mandatory)] [string]$HostName,
        [Parameter(Mandatory)] [string]$Path,
        [hashtable]$QueryParameters,
        [AllowEmptyString()] [string]$Body = '',
        [Parameter(Mandatory)] [string]$IKey,
        [Parameter(Mandatory)] [string]$SKey
    )

    $date = [DateTime]::UtcNow.ToString('r', [Globalization.CultureInfo]::InvariantCulture)
    $queryString = ConvertTo-DuoQueryString -Parameters $QueryParameters
    $upperMethod = $Method.ToUpperInvariant()
    $bodyForHash = if ($upperMethod -in @('GET', 'DELETE')) { '' } else { $Body }
    $bodyHash = Get-Sha512Hex -Value $bodyForHash
    $headersHash = Get-Sha512Hex -Value ''

    $canonical = @(
        $date
        $upperMethod
        $HostName.ToLowerInvariant()
        $Path
        $queryString
        $bodyHash
        $headersHash
    ) -join "`n"

    $hmac = [Security.Cryptography.HMACSHA512]::new([Text.Encoding]::UTF8.GetBytes($SKey))
    try {
        $signatureBytes = $hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonical))
        $signature = -join ($signatureBytes | ForEach-Object { $_.ToString('x2') })
    }
    finally {
        $hmac.Dispose()
    }

    $basicValue = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$IKey`:$signature"))
    return @{
        Date          = $date
        Authorization = "Basic $basicValue"
        Accept        = 'application/json'
    }
}

function Invoke-DuoApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('GET', 'POST')] [string]$Method,
        [Parameter(Mandatory)] [string]$HostName,
        [Parameter(Mandatory)] [string]$Path,
        [hashtable]$QueryParameters = @{},
        [hashtable]$BodyParameters = @{},
        [Parameter(Mandatory)] [string]$IKey,
        [Parameter(Mandatory)] [string]$SKey
    )

    $queryString = ConvertTo-DuoQueryString -Parameters $QueryParameters
    $uri = "https://$HostName$Path"
    if ($queryString) { $uri = "$uri`?$queryString" }

    $body = if ($Method -eq 'POST') {
        if ($BodyParameters.Count -eq 0) { '{}' }
        else { $BodyParameters | ConvertTo-Json -Compress }
    } else { '' }

    $headers = New-DuoV5Headers -Method $Method -HostName $HostName -Path $Path `
        -QueryParameters $QueryParameters -Body $body -IKey $IKey -SKey $SKey

    try {
        if ($Method -eq 'POST') {
            $result = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers `
                -ContentType 'application/json' -Body $body
        }
        else {
            $result = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
        }
    }
    catch {
        $statusCode = $null
        if ($_.Exception.Response) {
            try { $statusCode = [int]$_.Exception.Response.StatusCode } catch { }
        }
        $detail = if ($statusCode) { "HTTP $statusCode" } else { $_.Exception.Message }
        throw "Duo API request failed ($detail): $Method $HostName$Path"
    }

    if ($result.stat -ne 'OK') {
        throw "Duo API returned failure for $Method ${Path}: $($result.message)"
    }
    return $result
}

function Get-DuoSubaccountUsers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]$Subaccount,
        [Parameter(Mandatory)] [string]$IKey,
        [Parameter(Mandatory)] [string]$SKey
    )

    $users = [Collections.Generic.List[object]]::new()
    $offset = 0
    do {
        $parameters = @{
            account_id = [string]$Subaccount.account_id
            limit      = '300'
            offset     = [string]$offset
        }
        $result = Invoke-DuoApi -Method GET -HostName ([string]$Subaccount.api_hostname) `
            -Path '/admin/v1/users' -QueryParameters $parameters -IKey $IKey -SKey $SKey
        foreach ($user in @($result.response)) { $users.Add($user) }

        $nextOffset = $result.metadata.next_offset
        if ($null -ne $nextOffset) { $offset = [int]$nextOffset }
    } while ($null -ne $nextOffset)

    return $users
}

try {
    if (-not (Test-Path -LiteralPath $OutputDirectory)) {
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:LogPath = Join-Path $OutputDirectory "DuoMSP-UserUsage-$timestamp.log"
    $summaryPath = Join-Path $OutputDirectory "DuoMSP-ClientUsage-$timestamp.csv"
    $detailPath = Join-Path $OutputDirectory "DuoMSP-UserInventory-$timestamp.csv"

    $ApiHostname = $ApiHostname.Trim().ToLowerInvariant()
    $IntegrationKey = $IntegrationKey.Trim()

    if (-not $SecretKey) {
        $secureSecret = Read-Host 'Enter the Duo Admin API secret key' -AsSecureString
        $SecretKey = ConvertFrom-SecureValue -SecureValue $secureSecret
    }
    if ([string]::IsNullOrWhiteSpace($SecretKey)) {
        throw 'A Duo Admin API secret key was not supplied.'
    }

    Write-Log 'Starting Duo MSP user usage export.'
    Write-Log 'Retrieving Duo MSP subaccounts...'
    $subaccountResult = Invoke-DuoApi -Method POST -HostName $ApiHostname `
        -Path '/accounts/v1/account/list' -IKey $IntegrationKey -SKey $SecretKey
    $subaccounts = @($subaccountResult.response)
    Write-Log "Retrieved $($subaccounts.Count) subaccounts."

    $details = [Collections.Generic.List[object]]::new()
    $summary = [Collections.Generic.List[object]]::new()
    $reportDate = Get-Date -Format 'yyyy-MM-dd'

    foreach ($subaccount in $subaccounts) {
        Write-Log "Retrieving users for $($subaccount.name)..."
        $users = @(Get-DuoSubaccountUsers -Subaccount $subaccount -IKey $IntegrationKey -SKey $SecretKey)

        $editionResult = Invoke-DuoApi -Method GET -HostName ([string]$subaccount.api_hostname) `
            -Path '/admin/v1/billing/edition' `
            -QueryParameters @{ account_id = [string]$subaccount.account_id } `
            -IKey $IntegrationKey -SKey $SecretKey
        $edition = [string]$editionResult.response.edition

        foreach ($user in $users) {
            $lastLogin = $null
            if ($user.last_login) {
                try { $lastLogin = [DateTimeOffset]::FromUnixTimeSeconds([int64]$user.last_login).LocalDateTime } catch { }
            }

            $details.Add([pscustomobject]@{
                ReportDate       = $reportDate
                ClientName       = $subaccount.name
                AccountId        = $subaccount.account_id
                ApiHostname      = $subaccount.api_hostname
                Edition          = $edition
                UserId           = $user.user_id
                Username         = $user.username
                Email            = $user.email
                RealName         = $user.realname
                Status           = $user.status
                IsEnrolled       = [bool]$user.is_enrolled
                LastLogin        = if ($lastLogin) { $lastLogin.ToString('yyyy-MM-dd HH:mm:ss') } else { $null }
                LockoutReason    = $user.lockout_reason
                DirectoryManaged = -not [string]::IsNullOrWhiteSpace([string]$user.directory_key)
            })
        }

        $active = @($users | Where-Object status -eq 'active').Count
        $bypass = @($users | Where-Object status -eq 'bypass').Count
        $disabled = @($users | Where-Object status -eq 'disabled').Count
        $locked = @($users | Where-Object status -eq 'locked out').Count
        $pendingDeletion = @($users | Where-Object status -eq 'pending deletion').Count
        $enrolled = @($users | Where-Object is_enrolled).Count
        $notEnrolled = $users.Count - $enrolled

        $summary.Add([pscustomobject]@{
            ReportDate             = $reportDate
            ClientName             = $subaccount.name
            AccountId              = $subaccount.account_id
            ApiHostname            = $subaccount.api_hostname
            Edition                = $edition
            TotalUserObjects       = $users.Count
            ActiveUsers            = $active
            BypassUsers            = $bypass
            DisabledUsers          = $disabled
            LockedOutUsers         = $locked
            PendingDeletionUsers   = $pendingDeletion
            EnrolledUsers          = $enrolled
            NotEnrolledUsers       = $notEnrolled
            ProtectedUserEstimate  = $active + $bypass + $locked
            UsageCountingNote      = 'Inventory estimate; reconcile with Duo billing definition.'
        })
    }

    $summary | Sort-Object ClientName |
        Export-Csv -LiteralPath $summaryPath -NoTypeInformation -Encoding UTF8
    $details | Sort-Object ClientName, Username |
        Export-Csv -LiteralPath $detailPath -NoTypeInformation -Encoding UTF8

    $totalUsers = ($summary | Measure-Object -Property TotalUserObjects -Sum).Sum
    Write-Log "Duo subaccounts reported: $($summary.Count)" -Level SUCCESS
    Write-Log "Total user objects: $totalUsers" -Level SUCCESS
    Write-Log "Client usage report: $summaryPath" -Level SUCCESS
    Write-Log "Detailed user inventory: $detailPath" -Level SUCCESS
    Write-Log 'Duo MSP user usage export completed.' -Level SUCCESS

    [pscustomobject]@{
        ClientUsageCsv = $summaryPath
        UserInventoryCsv = $detailPath
        LogFile = $script:LogPath
        Subaccounts = $summary.Count
        TotalUserObjects = $totalUsers
    }
}
catch {
    Write-Log $_.Exception.Message -Level ERROR
    throw
}
finally {
    $SecretKey = $null
    $secureSecret = $null
}
