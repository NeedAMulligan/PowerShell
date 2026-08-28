[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ApiKey,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputDirectory = 'C:\Temp',

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^https://')]
    [string]$BaseUrl = 'https://app.infimasecapis.com'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:LogFile = $null

function Write-UsageLog {
    param(
        [Parameter(Mandatory)] [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')] [string]$Level = 'INFO'
    )

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
    if ($script:LogFile) {
        Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8
    }
}

function ConvertFrom-SecureStringToPlainText {
    param([Parameter(Mandatory)] [Security.SecureString]$SecureValue)

    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
    try {
        [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function Invoke-InfimaGet {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [hashtable]$Headers,
        [hashtable]$Query = @{}
    )

    $queryParts = foreach ($entry in $Query.GetEnumerator()) {
        '{0}={1}' -f [Uri]::EscapeDataString([string]$entry.Key), [Uri]::EscapeDataString([string]$entry.Value)
    }
    $uri = '{0}/{1}' -f $BaseUrl.TrimEnd('/'), $Path.TrimStart('/')
    if ($queryParts) {
        $uri = '{0}?{1}' -f $uri, ($queryParts -join '&')
    }

    Invoke-RestMethod -Method Get -Uri $uri -Headers $Headers -ContentType 'application/json'
}

function Get-InfimaPagedItems {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [hashtable]$Headers,
        [hashtable]$AdditionalQuery = @{}
    )

    $items = [Collections.Generic.List[object]]::new()
    $offset = 0
    $limit = 50

    do {
        $query = @{ limit = $limit; offset = $offset }
        foreach ($key in $AdditionalQuery.Keys) {
            $query[$key] = $AdditionalQuery[$key]
        }

        $response = Invoke-InfimaGet -Path $Path -Headers $Headers -Query $query
        $pageItems = @($response.items)
        foreach ($item in $pageItems) {
            $items.Add($item)
        }

        $offset += $pageItems.Count
        $total = if ($null -ne $response.total) { [int]$response.total } else { $offset }
    } while ($pageItems.Count -gt 0 -and $offset -lt $total)

    $items.ToArray()
}

function Get-OptionalValue {
    param(
        [Parameter(Mandatory)] [object]$InputObject,
        [Parameter(Mandatory)] [string]$PropertyName
    )

    $property = $InputObject.PSObject.Properties[$PropertyName]
    if ($null -ne $property) { return $property.Value }
    return $null
}

try {
    if (-not (Test-Path -LiteralPath $OutputDirectory)) {
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $summaryFile = Join-Path $OutputDirectory "INFIMA-ClientUsage-$timestamp.csv"
    $detailFile = Join-Path $OutputDirectory "INFIMA-UserInventory-$timestamp.csv"
    $script:LogFile = Join-Path $OutputDirectory "INFIMA-Usage-$timestamp.log"
    New-Item -ItemType File -Path $script:LogFile -Force | Out-Null

    Write-UsageLog 'Starting INFIMA partner usage export.'

    if ([string]::IsNullOrWhiteSpace($ApiKey)) {
        $secureApiKey = Read-Host 'Enter the INFIMA Partner API key' -AsSecureString
        $ApiKey = ConvertFrom-SecureStringToPlainText -SecureValue $secureApiKey
        $secureApiKey.Dispose()
    }
    if ([string]::IsNullOrWhiteSpace($ApiKey)) {
        throw 'An INFIMA API key is required.'
    }

    $headers = @{ 'X-API-Key' = $ApiKey; Accept = 'application/json' }
    $partner = Invoke-InfimaGet -Path '/v1/partner' -Headers $headers
    $partnerName = [string](Get-OptionalValue -InputObject $partner -PropertyName 'partner_name')
    Write-UsageLog ("Authenticated to INFIMA partner: {0}" -f $partnerName)

    $clients = @(Get-InfimaPagedItems -Path '/v1/clients' -Headers $headers)
    Write-UsageLog ("Found {0} client(s)." -f $clients.Count)

    $summaryRows = [Collections.Generic.List[object]]::new()
    $detailRows = [Collections.Generic.List[object]]::new()
    $reportDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    foreach ($client in $clients) {
        $clientId = [string](Get-OptionalValue -InputObject $client -PropertyName 'id')
        $clientName = [string](Get-OptionalValue -InputObject $client -PropertyName 'client_name')
        Write-UsageLog ("Collecting users for {0} ({1})." -f $clientName, $clientId)

        $users = @(Get-InfimaPagedItems -Path "/v1/clients/$clientId/users" -Headers $headers -AdditionalQuery @{ status = 'all' })
        $activeUsers = @($users | Where-Object { [string](Get-OptionalValue $_ 'status') -ieq 'active' }).Count
        $inactiveUsers = @($users | Where-Object { [string](Get-OptionalValue $_ 'status') -ieq 'inactive' }).Count
        $trainingOnTrack = @($users | Where-Object { (Get-OptionalValue $_ 'training_on_track') -eq $true }).Count
        $trainingBehind = @($users | Where-Object { (Get-OptionalValue $_ 'training_on_track') -eq $false }).Count

        $summaryRows.Add([pscustomobject][ordered]@{
            ReportDate                       = $reportDate
            PartnerName                      = $partnerName
            ClientId                         = $clientId
            ClientName                       = $clientName
            BillableActiveUsersEstimate      = $activeUsers
            TotalUserObjects                 = $users.Count
            ActiveUsers                      = $activeUsers
            InactiveUsers                    = $inactiveUsers
            ApiReportedUserCount             = Get-OptionalValue $client 'user_count'
            ApiReportedInactiveUserCount     = Get-OptionalValue $client 'inactive_user_count'
            TrainingOnTrackUsers             = $trainingOnTrack
            TrainingBehindUsers              = $trainingBehind
            TrainingOnTrackRate              = Get-OptionalValue $client 'training_on_track_rate'
            PhishingClickRateTotal           = Get-OptionalValue $client 'phishing_click_rate_total'
            PhishingClickRateLastYear        = Get-OptionalValue $client 'phishing_click_rate_last_year'
            ClientCreatedDate                = Get-OptionalValue $client 'created_date'
            UsageCountingNote                = 'Active users are a usage estimate; reconcile with the INFIMA contract and invoice rules.'
        })

        foreach ($user in $users) {
            $detailRows.Add([pscustomobject][ordered]@{
                ReportDate                    = $reportDate
                PartnerName                   = $partnerName
                ClientId                      = $clientId
                ClientName                    = $clientName
                UserId                        = Get-OptionalValue $user 'id'
                Email                         = Get-OptionalValue $user 'email'
                FirstName                     = Get-OptionalValue $user 'first_name'
                LastName                      = Get-OptionalValue $user 'last_name'
                Department                    = Get-OptionalValue $user 'department'
                Status                        = Get-OptionalValue $user 'status'
                PreferredLanguage             = Get-OptionalValue $user 'preferred_language'
                Role                          = Get-OptionalValue $user 'role'
                CreatedDate                   = Get-OptionalValue $user 'created_date'
                TrainingOnTrack               = Get-OptionalValue $user 'training_on_track'
                NextCourse                    = Get-OptionalValue $user 'next_course'
                CoursesBehind                 = Get-OptionalValue $user 'courses_behind'
                RiskScore                     = Get-OptionalValue $user 'risk_score'
                PhishingClickRateTotal        = Get-OptionalValue $user 'phishing_click_rate_total'
                PhishingClickRateLastYear     = Get-OptionalValue $user 'phishing_click_rate_last_year'
            })
        }
    }

    $summaryRows | Sort-Object ClientName | Export-Csv -LiteralPath $summaryFile -NoTypeInformation -Encoding UTF8
    $detailRows | Sort-Object ClientName, Email | Export-Csv -LiteralPath $detailFile -NoTypeInformation -Encoding UTF8

    Write-UsageLog ("Client summary saved to {0}" -f $summaryFile)
    Write-UsageLog ("User inventory saved to {0}" -f $detailFile)
    Write-UsageLog 'INFIMA partner usage export completed successfully.'

    [pscustomobject]@{
        PartnerName      = $partnerName
        Clients          = $clients.Count
        Users            = $detailRows.Count
        ClientUsageCsv   = $summaryFile
        UserInventoryCsv = $detailFile
        LogFile          = $script:LogFile
    }
}
catch {
    Write-UsageLog -Level ERROR -Message $_.Exception.Message
    throw
}
finally {
    $ApiKey = $null
    $headers = $null
}
