#requires -Version 5.1

<#
.SYNOPSIS
    Exports current Keeper MSP managed-company usage from Keeper Government Cloud.

.DESCRIPTION
    Uses Keeper Security's PowerCommander PowerShell module to authenticate to
    govcloud.keepersecurity.us and retrieve the current managed-company usage
    snapshot with Get-KeeperManagedCompany -Detailed. It then switches into
    each managed company and retrieves its enterprise-user inventory.

    Authentication is interactive. For SSO accounts, PowerCommander displays a
    Government Cloud SSO URL. Open that URL in a browser, complete SSO, paste the
    resulting one-time token only into the local PowerShell prompt, and enter
    keeper_push when PowerCommander requests SSO Login Approval. Approve the
    Keeper notification on the registered device.

    Never paste an SSO URL, SSO token, Keeper Push approval, master password,
    MFA code, or session credential into a ticket, chat, email, or report.
    This script does not request, capture, log, or store those values.

    PowerCommander 1.1.6 Get-MspBillingReport currently returns HTTP 405 for
    Keeper Government Cloud billing endpoints. Therefore, this script produces
    a point-in-time usage snapshot and does not call Get-MspBillingReport.

    Output is written to C:\Temp by default with timestamped filenames:
      - normalized client usage CSV
      - raw PowerCommander managed-company CSV
      - detailed user inventory CSV
      - execution log

.PARAMETER KeeperUsername
    Keeper MSP administrator username. If omitted, the script prompts for it.

.PARAMETER OutputDirectory
    Report destination. Defaults to C:\Temp.

.PARAMETER DisconnectWhenComplete
    Disconnects and clears the in-memory PowerCommander session after export.

.EXAMPLE
    .\Export-KeeperMSP-Gov-Usage-v1.2.0.ps1 `
        -KeeperUsername 'admin@example.com'

.EXAMPLE
    .\Export-KeeperMSP-Gov-Usage-v1.2.0.ps1 `
        -KeeperUsername 'admin@example.com' `
        -DisconnectWhenComplete

.NOTES
    Prerequisite:
      Install-Module -Name PowerCommander -Scope CurrentUser

    Interactive SSO workflow:
      1. The script connects only to govcloud.keepersecurity.us.
      2. Open the displayed GOV SSO URL in a browser.
      3. Complete organizational SSO.
      4. Paste the one-time SSO token into PowerShell only.
      5. At SSO Login Approval, enter: keeper_push
      6. Approve the Keeper notification and resume when prompted.

    Reporting basis:
      AllocatedLicenses = seats allocated to the managed company.
      ActiveUsers       = current active/consumed users.
      ActiveUsers       = users whose Keeper UserStatus is Active.
      InactiveUsers     = users whose Keeper UserStatus is Inactive.
      BillableUsage     = ActiveUsers as a current usage estimate.
      RemainingLicenses = AllocatedLicenses minus ActiveUsers.

    Keeper often shows an invited but not activated user as Inactive. The
    export preserves Keeper's raw UserStatus and labels this count
    InactiveOrPendingUsers rather than asserting that every inactive account
    is a pending invitation.

    This snapshot is not Keeper's contractual historical billing statement.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$KeeperUsername,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputDirectory = 'C:\Temp',

    [Parameter()]
    [switch]$DisconnectWhenComplete
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$script:LogPath = $null
$keeperGovServer = 'govcloud.keepersecurity.us'

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

function Get-PropertyValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]$InputObject,
        [Parameter(Mandatory)] [string[]]$Names
    )

    foreach ($name in $Names) {
        $property = $InputObject.PSObject.Properties[$name]
        if ($property) {
            return $property.Value
        }
    }
    return $null
}

function Convert-ToInteger {
    [CmdletBinding()]
    param([AllowNull()] [object]$Value)

    $result = 0
    [void][int]::TryParse([string]$Value, [ref]$result)
    return $result
}

try {
    if (-not (Test-Path -LiteralPath $OutputDirectory)) {
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:LogPath = Join-Path $OutputDirectory "KeeperMSP-Gov-Usage-$timestamp.log"
    $rawPath = Join-Path $OutputDirectory "KeeperMSP-Gov-Raw-$timestamp.csv"
    $summaryPath = Join-Path $OutputDirectory "KeeperMSP-Gov-ClientUsage-$timestamp.csv"
    $userPath = Join-Path $OutputDirectory "KeeperMSP-Gov-UserInventory-$timestamp.csv"

    Write-Log 'Starting Keeper MSP Government Cloud current-usage export.'

    $module = Get-Module -ListAvailable -Name PowerCommander |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if (-not $module) {
        throw @'
PowerCommander is not installed. Install the official Keeper module with:
  Install-Module -Name PowerCommander -Scope CurrentUser
'@
    }

    Import-Module PowerCommander -MinimumVersion $module.Version -Force
    Write-Log "Loaded PowerCommander version $($module.Version)."

    foreach ($requiredCommand in @(
        'Connect-Keeper',
        'Get-KeeperManagedCompany',
        'Get-KeeperEnterpriseUser',
        'Switch-KeeperMC',
        'Switch-KeeperMSP',
        'Disconnect-Keeper'
    )) {
        if (-not (Get-Command -Name $requiredCommand -ErrorAction SilentlyContinue)) {
            throw "Required PowerCommander command is unavailable: $requiredCommand"
        }
    }

    if ([string]::IsNullOrWhiteSpace($KeeperUsername)) {
        $KeeperUsername = Read-Host 'Enter the Keeper MSP administrator username'
    }
    if ([string]::IsNullOrWhiteSpace($KeeperUsername)) {
        throw 'A Keeper MSP administrator username is required.'
    }

    Write-Host ''
    Write-Host 'Keeper Government Cloud SSO instructions:' -ForegroundColor Cyan
    Write-Host '  1. Open the GOV SSO URL displayed by PowerCommander.'
    Write-Host '  2. Complete SSO in the browser.'
    Write-Host '  3. Paste the one-time SSO token into this PowerShell window only.'
    Write-Host '  4. At SSO Login Approval, enter: keeper_push'
    Write-Host '  5. Approve the Keeper notification and resume when prompted.'
    Write-Host '  Never share or save the SSO URL, token, approval, password, or MFA code.' -ForegroundColor Yellow
    Write-Host ''

    Write-Log "Connecting to Keeper Government Cloud as $KeeperUsername."
    Connect-Keeper -Server $keeperGovServer -Username $KeeperUsername

    Write-Log 'Authentication completed. Requesting managed-company usage snapshot...'
    $rawRows = @(Get-KeeperManagedCompany -Detailed)
    if ($rawRows.Count -eq 0) {
        throw 'Keeper returned no managed companies. Confirm that the account is an MSP administrator.'
    }

    $rawRows | Sort-Object company_name |
        Export-Csv -LiteralPath $rawPath -NoTypeInformation -Encoding UTF8

    $userInventory = [Collections.Generic.List[object]]::new()
    foreach ($company in $rawRows) {
        $companyId = Get-PropertyValue $company @('company_id', 'EnterpriseId')
        $companyName = [string](Get-PropertyValue $company @('company_name', 'EnterpriseName'))

        try {
            Write-Log "Retrieving enterprise users for managed company: $companyName"
            Switch-KeeperMC $companyName | Out-Null

            $companyUsers = @(Get-KeeperEnterpriseUser)
            foreach ($user in $companyUsers) {
                $userStatus = [string](Get-PropertyValue $user @('UserStatus', 'Status'))
                $userInventory.Add([pscustomobject]@{
                    ReportDate              = Get-Date -Format 'yyyy-MM-dd'
                    Platform                = 'Keeper Government Cloud'
                    ManagedCompanyId        = $companyId
                    ManagedCompanyName      = $companyName
                    Email                   = Get-PropertyValue $user @('Email', 'Username')
                    DisplayName             = Get-PropertyValue $user @('DisplayName', 'Name')
                    UserStatus              = $userStatus
                    IsActive                = $userStatus -eq 'Active'
                    IsInactiveOrPending     = $userStatus -eq 'Inactive'
                    NodeName                = Get-PropertyValue $user @('NodeName', 'Node')
                    TwoFactorEnabled        = Get-PropertyValue $user @('TwoFactorEnabled')
                    TransferStatus          = Get-PropertyValue $user @('TransferStatus')
                    TransferAcceptanceStatus = Get-PropertyValue $user @('TransferAcceptanceStatus')
                    IsTransferAccepted      = Get-PropertyValue $user @('IsTransferAccepted')
                    KeeperEnterpriseUserId  = Get-PropertyValue $user @('Id', 'EnterpriseUserId')
                })
            }

            Write-Log "Users returned for ${companyName}: $($companyUsers.Count)"
        }
        catch {
            Write-Log "Unable to retrieve users for '$companyName': $($_.Exception.Message)" -Level WARNING
        }
        finally {
            try {
                Switch-KeeperMSP | Out-Null
            }
            catch {
                Write-Log "Unable to return to the MSP context after '$companyName': $($_.Exception.Message)" -Level WARNING
            }
        }
    }

    $userInventory | Sort-Object ManagedCompanyName, Email |
        Export-Csv -LiteralPath $userPath -NoTypeInformation -Encoding UTF8

    $reportDate = Get-Date -Format 'yyyy-MM-dd'
    $summary = @(foreach ($row in $rawRows) {
        $allocated = Convert-ToInteger (Get-PropertyValue $row @('allocated', 'NumberOfSeats'))
        $keeperReportedActive = Convert-ToInteger (Get-PropertyValue $row @('active', 'NumberOfUsers'))
        $companyId = Get-PropertyValue $row @('company_id', 'EnterpriseId')
        $companyUsers = @($userInventory | Where-Object { $_.ManagedCompanyId -eq $companyId })
        $activeUsers = @($companyUsers | Where-Object { $_.UserStatus -eq 'Active' }).Count
        $inactiveUsers = @($companyUsers | Where-Object { $_.UserStatus -eq 'Inactive' }).Count
        $lockedUsers = @($companyUsers | Where-Object { $_.UserStatus -eq 'Locked' }).Count
        $disabledUsers = @($companyUsers | Where-Object { $_.UserStatus -eq 'Disabled' }).Count
        $otherStatusUsers = @($companyUsers | Where-Object {
            $_.UserStatus -notin @('Active', 'Inactive', 'Locked', 'Disabled')
        }).Count
        $isUnlimited = $allocated -lt 0
        $remaining = if ($isUnlimited) { $null } else { [Math]::Max(0, $allocated - $keeperReportedActive) }

        [pscustomobject]@{
            ReportDate          = $reportDate
            Platform            = 'Keeper Government Cloud'
            UsageType           = 'Current Snapshot'
            ManagedCompanyId    = $companyId
            ManagedCompanyName  = Get-PropertyValue $row @('company_name', 'EnterpriseName')
            Node                = Get-PropertyValue $row @('node_name', 'node', 'NodeName')
            Plan                = Get-PropertyValue $row @('plan', 'ProductId')
            StoragePlan         = Get-PropertyValue $row @('storage', 'FilePlanType')
            AddOns              = Get-PropertyValue $row @('addons', 'Addons')
            AllocatedLicenses   = $allocated
            KeeperReportedActive = $keeperReportedActive
            EnumeratedUsers     = $companyUsers.Count
            ActiveUsers         = $activeUsers
            InactiveOrPendingUsers = $inactiveUsers
            LockedUsers         = $lockedUsers
            DisabledUsers       = $disabledUsers
            OtherStatusUsers    = $otherStatusUsers
            BillableUsage       = $keeperReportedActive
            RemainingLicenses   = $remaining
            UnlimitedAllocation = $isUnlimited
            UtilizationPercent  = if (-not $isUnlimited -and $allocated -gt 0) {
                [Math]::Round(($keeperReportedActive / $allocated) * 100, 2)
            }
            else {
                $null
            }
            StatusDisclaimer    = 'Inactive may represent invited but not activated; see raw UserStatus.'
            BillingDisclaimer   = 'Current Keeper-reported active-user estimate; not historical billing statement.'
        }
    })

    $summary | Sort-Object ManagedCompanyName |
        Export-Csv -LiteralPath $summaryPath -NoTypeInformation -Encoding UTF8

    $totalAllocated = ($summary | Measure-Object -Property AllocatedLicenses -Sum).Sum
    $totalActive = ($summary | Measure-Object -Property KeeperReportedActive -Sum).Sum
    $totalRemaining = ($summary | Measure-Object -Property RemainingLicenses -Sum).Sum
    $totalEnumeratedUsers = $userInventory.Count
    $totalInactiveUsers = @($userInventory | Where-Object { $_.UserStatus -eq 'Inactive' }).Count

    Write-Log "Managed companies reported: $($summary.Count)" -Level SUCCESS
    Write-Log "Total allocated licenses: $totalAllocated" -Level SUCCESS
    Write-Log "Total active/current usage: $totalActive" -Level SUCCESS
    Write-Log "Total users enumerated: $totalEnumeratedUsers" -Level SUCCESS
    Write-Log "Total inactive or potentially pending users: $totalInactiveUsers" -Level SUCCESS
    Write-Log "Total remaining licenses: $totalRemaining" -Level SUCCESS
    Write-Log "Normalized usage report: $summaryPath" -Level SUCCESS
    Write-Log "Raw Keeper report: $rawPath" -Level SUCCESS
    Write-Log "Detailed user inventory: $userPath" -Level SUCCESS
    Write-Log 'Get-MspBillingReport was intentionally not called because it returns HTTP 405 on Keeper GOV.' -Level WARNING

    if ($DisconnectWhenComplete) {
        Disconnect-Keeper
        Write-Log 'Disconnected from Keeper and cleared the PowerCommander session.'
    }

    Write-Log 'Keeper MSP Government Cloud usage export completed.' -Level SUCCESS

    [pscustomobject]@{
        ClientUsageCsv        = $summaryPath
        RawKeeperCsv          = $rawPath
        UserInventoryCsv      = $userPath
        LogFile               = $script:LogPath
        ManagedCompanies      = $summary.Count
        TotalAllocatedSeats   = $totalAllocated
        TotalActiveUsers      = $totalActive
        TotalEnumeratedUsers  = $totalEnumeratedUsers
        TotalInactiveUsers    = $totalInactiveUsers
        TotalRemainingSeats   = $totalRemaining
        KeeperServer          = $keeperGovServer
        PowerCommanderVersion = [string]$module.Version
        ReportType            = 'Current Snapshot'
    }
}
catch {
    Write-Log $_.Exception.Message -Level ERROR
    throw
}
