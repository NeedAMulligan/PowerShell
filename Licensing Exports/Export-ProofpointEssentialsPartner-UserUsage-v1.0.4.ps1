#requires -Version 5.1
<#
.SYNOPSIS
    Exports current Proofpoint Essentials user-license usage for every child organization.

.DESCRIPTION
    Uses the Proofpoint Essentials Interface REST API with a partner administrator account.
    The script enumerates child organizations, retrieves their licensing data and users, and
    writes a normalized client summary, detailed user inventory, raw organization export,
    and execution log. All requests are read-only.

    The password is requested through a secure prompt unless supplied as a SecureString.
    Proofpoint requires the administrator username and password in X-User and X-Password
    headers on every API request. These values are never written to an output file or log.

.PARAMETER ApiHost
    Proofpoint Essentials stack hostname, such as us1.proofpointessentials.com.

.PARAMETER PartnerDomain
    Primary domain of the partner organization used to address the parent API resource.

.PARAMETER Username
    Proofpoint Essentials partner administrator username. If omitted, the script prompts.

.PARAMETER Password
    Optional SecureString containing the administrator password. If omitted, the script prompts.

.PARAMETER OutputDirectory
    Destination directory. Defaults to C:\Temp.

.EXAMPLE
    .\Export-ProofpointEssentialsPartner-UserUsage-v1.0.4.ps1 `
        -ApiHost "us1.proofpointessentials.com" `
        -PartnerDomain "partner.example.com" `
        -Username "apiadmin@partner.example.com"

.NOTES
    Required role: Proofpoint Essentials Channel, Strategic, or OEM Partner Administrator
    with API access to the child organizations.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^(?:https?://)?[A-Za-z0-9.-]+\.proofpointessentials\.com/?$')]
    [string]$ApiHost,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PartnerDomain,

    [Parameter()]
    [string]$Username,

    [Parameter()]
    [Security.SecureString]$Password,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputDirectory = 'C:\Temp'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
}

$summaryPath = Join-Path $OutputDirectory "ProofpointEssentials-ClientUsage-$timestamp.csv"
$usersPath = Join-Path $OutputDirectory "ProofpointEssentials-UserInventory-$timestamp.csv"
$allAccountsPath = Join-Path $OutputDirectory "ProofpointEssentials-AllAccounts-Audit-$timestamp.csv"
$rawPath = Join-Path $OutputDirectory "ProofpointEssentials-Organizations-Raw-$timestamp.json"
$logPath = Join-Path $OutputDirectory "ProofpointEssentials-Usage-$timestamp.log"

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR')][string]$Level = 'INFO'
    )
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
}

function ConvertFrom-SecureValue {
    param([Parameter(Mandatory = $true)][Security.SecureString]$SecureValue)
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
    try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function Get-PropertyValue {
    param($Object, [string[]]$Names, $Default = $null)
    if ($null -eq $Object) { return $Default }
    foreach ($name in $Names) {
        $property = $Object.PSObject.Properties[$name]
        if ($null -ne $property -and $null -ne $property.Value -and "$($property.Value)" -ne '') {
            return $property.Value
        }
    }
    return $Default
}

function ConvertTo-Boolean {
    param($Value, [bool]$Default = $false)
    if ($null -eq $Value -or "$Value" -eq '') { return $Default }
    if ($Value -is [bool]) { return $Value }
    return "$Value" -match '^(?i:true|1|yes)$'
}

function Invoke-ProofpointGet {
    param([Parameter(Mandatory = $true)][string]$Path)
    $normalizedApiHost = $ApiHost.Trim() -replace '^https?://', ''
    $uri = 'https://{0}/api/v1/{1}' -f $normalizedApiHost.TrimEnd('/'), $Path.TrimStart('/')
    try {
        return Invoke-RestMethod -Method Get -Uri $uri -Headers $script:apiHeaders -ContentType 'application/json' -UseBasicParsing
    }
    catch {
        $status = $null
        if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
        $detail = if ($status) { "HTTP $status" } else { $_.Exception.Message }
        throw "Proofpoint Essentials API request failed ($detail): $uri"
    }
}

function Get-OrganizationDomain {
    param($Organization)
    $direct = Get-PropertyValue $Organization @('primary_domain', 'primaryDomain', 'domain', 'domain_name')
    if ($direct) { return "$direct" }

    $domains = @(Get-PropertyValue $Organization @('domains') @())
    foreach ($domain in $domains) {
        if ($domain -is [string]) { return "$domain" }
        $isPrimary = ConvertTo-Boolean (Get-PropertyValue $domain @('is_primary', 'primary') $false)
        if ($isPrimary) { return "$(Get-PropertyValue $domain @('name', 'domain_name'))" }
    }
    if ($domains.Count -gt 0) {
        $first = $domains[0]
        if ($first -is [string]) { return "$first" }
        return "$(Get-PropertyValue $first @('name', 'domain_name'))"
    }
    return $null
}

Write-Log 'Starting Proofpoint Essentials partner usage export.'
if ([string]::IsNullOrWhiteSpace($Username)) { $Username = Read-Host 'Enter the Proofpoint Essentials partner administrator username' }
if ($null -eq $Password) { $Password = Read-Host 'Enter the Proofpoint Essentials administrator password' -AsSecureString }

$plainPassword = ConvertFrom-SecureValue -SecureValue $Password
try {
    $script:apiHeaders = @{
        'X-User'         = $Username
        'X-Password'     = $plainPassword
        'X-Terms-Update' = 'true'
        'Accept'         = 'application/json'
    }

    $encodedPartner = [Uri]::EscapeDataString($PartnerDomain.Trim().ToLowerInvariant())
    Write-Log "Retrieving child organizations beneath $PartnerDomain..."
    $organizationResponse = Invoke-ProofpointGet -Path "orgs/$encodedPartner/orgs"
    $organizations = @(
        if ($organizationResponse.PSObject.Properties['orgs']) { $organizationResponse.orgs }
        elseif ($organizationResponse.PSObject.Properties['organizations']) { $organizationResponse.organizations }
        elseif ($organizationResponse -is [Array]) { $organizationResponse }
        else { $organizationResponse }
    )

    $organizations | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $rawPath -Encoding UTF8
    $summary = New-Object System.Collections.Generic.List[object]
    $inventory = New-Object System.Collections.Generic.List[object]
    $allAccounts = New-Object System.Collections.Generic.List[object]

    foreach ($organization in $organizations) {
        $orgName = "$(Get-PropertyValue $organization @('name', 'organization_name', 'company_name') 'Unknown')"
        $orgDomain = Get-OrganizationDomain $organization
        if ([string]::IsNullOrWhiteSpace($orgDomain)) {
            Write-Log "Skipping '$orgName' because its primary domain was not returned." 'WARNING'
            continue
        }

        Write-Log "Retrieving licensing and users for: $orgName ($orgDomain)"
        $encodedDomain = [Uri]::EscapeDataString($orgDomain.ToLowerInvariant())
        $licensing = $null
        try { $licensing = Invoke-ProofpointGet -Path "orgs/$encodedDomain/licensing" }
        catch { Write-Log "Licensing endpoint unavailable for '$orgName': $($_.Exception.Message)" 'WARNING' }

        $userResponse = $null
        $users = @()
        $userDataStatus = 'Retrieved'
        try {
            $userResponse = Invoke-ProofpointGet -Path "orgs/$encodedDomain/users"

            # Proofpoint can return no body, an empty users property, one user,
            # or an array. Force all valid results into a real array so a
            # provisioned child organization with no migrated users reports 0.
            if ($null -eq $userResponse) {
                $users = @()
                $userDataStatus = 'No users returned'
            }
            elseif ($userResponse.PSObject.Properties['users']) {
                $users = @($userResponse.users | Where-Object { $null -ne $_ })
            }
            elseif ($userResponse -is [Array]) {
                $users = @($userResponse | Where-Object { $null -ne $_ })
            }
            elseif ($userResponse.PSObject.Properties['primary_email'] -or
                    $userResponse.PSObject.Properties['email'] -or
                    $userResponse.PSObject.Properties['uid']) {
                $users = @($userResponse)
            }
            else {
                Write-Log "No user records were returned for '$orgName'; recording zero users." 'WARNING'
                $users = @()
                $userDataStatus = 'No users returned'
            }
        }
        catch {
            # Some Essentials child organizations exist before mailbox/user
            # migration and reject or do not expose the users endpoint. Keep
            # the organization in the report with zero users and continue.
            Write-Log "Users could not be retrieved for '$orgName'; recording zero users and continuing. $($_.Exception.Message)" 'WARNING'
            $users = @()
            $userDataStatus = 'Unavailable - review warning log'
        }
        if ($userDataStatus -eq 'Retrieved' -and @($users).Count -eq 0) {
            $userDataStatus = 'No users returned'
        }

        $active = 0; $inactive = 0; $billable = 0; $activeBillable = 0; $nonBillable = 0
        $endUsers = 0; $silentUsers = 0; $adminUsers = 0; $functionalAccounts = 0
        $portalActiveUsers = 0
        foreach ($user in $users) {
            $isActive = ConvertTo-Boolean (Get-PropertyValue $user @('is_active', 'isactive') $false)
            $isBillable = ConvertTo-Boolean (Get-PropertyValue $user @('is_billable') $true) $true
            $userType = "$(Get-PropertyValue $user @('type', 'role', 'user_type') '')"
            $isFunctionalAccount = $userType -match '^(?i:functional_account)$'
            # Proofpoint Essentials Customer Overview counts active users of
            # every type except functional_account. This includes end users,
            # silent users, organization admins, and channel admins.
            $isPortalActiveUser = $isActive -and -not $isFunctionalAccount
            if ($isActive) { $active++ } else { $inactive++ }
            if ($isBillable) { $billable++ } else { $nonBillable++ }
            if ($isActive -and $isBillable) { $activeBillable++ }
            if ($isPortalActiveUser) { $portalActiveUsers++ }
            if ($isActive -and $isFunctionalAccount) { $functionalAccounts++ }
            if ($isPortalActiveUser) {
                if ($userType -match '(?i)silent') { $silentUsers++ }
                elseif ($userType -match '(?i)admin') { $adminUsers++ }
                else { $endUsers++ }
            }

            $inventoryRecord = [pscustomobject]@{
                ReportDate          = (Get-Date).ToString('yyyy-MM-dd')
                ClientName          = $orgName
                PrimaryDomain       = $orgDomain
                PrimaryEmail        = "$(Get-PropertyValue $user @('primary_email', 'email'))"
                DisplayName         = "$(Get-PropertyValue $user @('name', 'display_name'))"
                UserType            = $userType
                IsActive            = $isActive
                IsBillable          = $isBillable
                IsFunctionalAccount = $isFunctionalAccount
                CountsAsActiveUser  = $isPortalActiveUser
                UserId              = "$(Get-PropertyValue $user @('uid', 'id'))"
            }
            $allAccounts.Add($inventoryRecord)
            if ($isPortalActiveUser) {
                $inventory.Add($inventoryRecord)
            }
        }

        $licensed = Get-PropertyValue $licensing @('user_licenses', 'licenses', 'licensed_users', 'number_of_licenses')
        $package = Get-PropertyValue $organization @('licensing_package', 'package', 'package_name')
        $isActiveOrg = ConvertTo-Boolean (Get-PropertyValue $organization @('is_active', 'isactive') $true) $true
        $summary.Add([pscustomobject]@{
            ReportDate                  = (Get-Date).ToString('yyyy-MM-dd')
            ClientName                  = $orgName
            PrimaryDomain               = $orgDomain
            OrganizationEid             = "$(Get-PropertyValue $organization @('eid', 'id'))"
            OrganizationActive          = $isActiveOrg
            Package                     = "$package"
            LicensedQuantity            = $licensed
            UserDataStatus              = $userDataStatus
            ActiveUsers                  = $portalActiveUsers
            ActiveEndUsers               = $endUsers
            ActiveSilentUsers            = $silentUsers
            ActiveAdminUsers             = $adminUsers
            ActiveFunctionalAccountsExcluded = $functionalAccounts
            AllApiAccountObjects          = @($users).Count
            UsageBasis                   = 'Active users excluding type functional_account'
        })
    }

    $summary | Sort-Object ClientName | Export-Csv -LiteralPath $summaryPath -NoTypeInformation -Encoding UTF8
    $inventory | Sort-Object ClientName, PrimaryEmail | Export-Csv -LiteralPath $usersPath -NoTypeInformation -Encoding UTF8
    $allAccounts | Sort-Object ClientName, PrimaryEmail | Export-Csv -LiteralPath $allAccountsPath -NoTypeInformation -Encoding UTF8

    $totalUsage = ($summary | Measure-Object -Property ActiveUsers -Sum).Sum
    Write-Log "Organizations reported: $($summary.Count)" 'SUCCESS'
    Write-Log "Portal-aligned active users: $totalUsage" 'SUCCESS'
    Write-Log "Client usage report: $summaryPath" 'SUCCESS'
    Write-Log "User inventory: $usersPath" 'SUCCESS'
    Write-Log "All-account audit inventory: $allAccountsPath" 'SUCCESS'
    Write-Log "Raw organization response: $rawPath" 'SUCCESS'
    Write-Log 'Proofpoint Essentials partner usage export completed.' 'SUCCESS'

    [pscustomobject]@{
        ClientUsageCsv             = $summaryPath
        UserInventoryCsv           = $usersPath
        AllAccountsAuditCsv        = $allAccountsPath
        RawOrganizationsJson       = $rawPath
        LogFile                    = $logPath
        Organizations             = $summary.Count
        PortalAlignedActiveUsers    = $totalUsage
        ApiHost                    = $ApiHost
    }
}
finally {
    $plainPassword = $null
    $script:apiHeaders = $null
}
