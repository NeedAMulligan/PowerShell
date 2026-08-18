#Requires -Modules Microsoft.Graph.Users

<#
.SYNOPSIS
    Export Microsoft 365 / Entra ID guest accounts with sign-in and age data.

.DESCRIPTION
    Retrieves all Entra ID users where UserType = Guest and reports:
      - Account status
      - Invitation / external user state
      - Account creation date
      - Guest account age
      - Last successful sign-in
      - Days since last successful sign-in
      - Stale status based on configurable threshold

.NOTES
    Required delegated Microsoft Graph permissions:
      - User.Read.All
      - AuditLog.Read.All

    SignInActivity may require Microsoft Entra ID P1 or P2 licensing.

    Output:
      C:\Temp\M365_GuestAccounts_yyyyMMdd_HHmmss.csv
#>

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

$OutputFolder   = "C:\Temp"
$StaleThreshold = 90

# ---------------------------------------------------------------------------
# Prepare output location
# ---------------------------------------------------------------------------

if (-not (Test-Path -Path $OutputFolder)) {
    New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
}

$Timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$OutputFile = Join-Path `
    -Path $OutputFolder `
    -ChildPath "M365_GuestAccounts_$Timestamp.csv"

# ---------------------------------------------------------------------------
# Connect to Microsoft Graph
# ---------------------------------------------------------------------------

Import-Module Microsoft.Graph.Users -ErrorAction Stop

Connect-MgGraph -Scopes @(
    "User.Read.All"
    "AuditLog.Read.All"
)

# Optional - show current Graph context
$MgContext = Get-MgContext

Write-Host ""
Write-Host "Connected to Microsoft Graph"
Write-Host "Tenant ID : $($MgContext.TenantId)"
Write-Host "Account   : $($MgContext.Account)"
Write-Host ""

# ---------------------------------------------------------------------------
# Retrieve guest accounts
# ---------------------------------------------------------------------------

Write-Host "Querying guest accounts..."

$GuestUsers = Get-MgUser `
    -Filter "userType eq 'Guest'" `
    -All `
    -Property @(
        "Id"
        "DisplayName"
        "UserPrincipalName"
        "Mail"
        "AccountEnabled"
        "CreatedDateTime"
        "ExternalUserState"
        "ExternalUserStateChangeDateTime"
        "SignInActivity"
    )

Write-Host "Found $($GuestUsers.Count) guest account(s)."
Write-Host ""

# ---------------------------------------------------------------------------
# Build report
# ---------------------------------------------------------------------------

$CurrentDate = Get-Date

$Report = foreach ($Guest in $GuestUsers) {

    # -----------------------------------------------------------------------
    # Guest age
    # -----------------------------------------------------------------------

    $GuestAgeDays = $null

    if ($Guest.CreatedDateTime) {
        $GuestAgeDays = [math]::Floor(
            ($CurrentDate - $Guest.CreatedDateTime).TotalDays
        )
    }

    # -----------------------------------------------------------------------
    # Last successful sign-in
    #
    # This is preferred over LastSignInDateTime because it represents the
    # last successful authentication rather than merely the last attempt.
    # -----------------------------------------------------------------------

    $LastSuccessfulSignIn = $null

    if ($Guest.SignInActivity.LastSuccessfulSignInDateTime) {
        $LastSuccessfulSignIn =
            $Guest.SignInActivity.LastSuccessfulSignInDateTime
    }

    # -----------------------------------------------------------------------
    # Days since successful sign-in
    # -----------------------------------------------------------------------

    $DaysSinceLastSignIn = $null

    if ($LastSuccessfulSignIn) {
        $DaysSinceLastSignIn = [math]::Floor(
            ($CurrentDate - $LastSuccessfulSignIn).TotalDays
        )
    }

    # -----------------------------------------------------------------------
    # Determine stale status
    # -----------------------------------------------------------------------

    if (-not $Guest.AccountEnabled) {
        $StaleStatus = "Disabled"
    }
    elseif ($Guest.ExternalUserState -eq "PendingAcceptance") {
        $StaleStatus = "Invitation Pending"
    }
    elseif (-not $LastSuccessfulSignIn) {

        if (
            $GuestAgeDays -ne $null -and
            $GuestAgeDays -ge $StaleThreshold
        ) {
            $StaleStatus = "Stale - Never Signed In"
        }
        else {
            $StaleStatus = "Never Signed In"
        }
    }
    elseif ($DaysSinceLastSignIn -ge $StaleThreshold) {
        $StaleStatus = "Stale"
    }
    else {
        $StaleStatus = "Active"
    }

    # -----------------------------------------------------------------------
    # Output object
    # -----------------------------------------------------------------------

    [PSCustomObject]@{
        DisplayName                      = $Guest.DisplayName
        UserPrincipalName                = $Guest.UserPrincipalName
        Mail                             = $Guest.Mail
        AccountEnabled                   = $Guest.AccountEnabled
        ExternalUserState                = $Guest.ExternalUserState
        ExternalUserStateChangeDateTime  = $Guest.ExternalUserStateChangeDateTime
        CreatedDateTime                  = $Guest.CreatedDateTime
        GuestAgeDays                     = $GuestAgeDays
        LastSuccessfulSignInDateTime     = $LastSuccessfulSignIn
        DaysSinceLastSuccessfulSignIn    = $DaysSinceLastSignIn
        StaleThresholdDays               = $StaleThreshold
        Status                           = $StaleStatus
        Id                               = $Guest.Id
    }
}

# ---------------------------------------------------------------------------
# Sort and display
# ---------------------------------------------------------------------------

$Report = $Report |
    Sort-Object `
        @{ Expression = "Status"; Descending = $false },
        @{ Expression = "DaysSinceLastSuccessfulSignIn"; Descending = $true }

$Report |
    Format-Table `
        DisplayName,
        UserPrincipalName,
        AccountEnabled,
        ExternalUserState,
        GuestAgeDays,
        LastSuccessfulSignInDateTime,
        DaysSinceLastSuccessfulSignIn,
        Status `
        -AutoSize

# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------

$Report |
    Export-Csv `
        -Path $OutputFile `
        -NoTypeInformation `
        -Encoding UTF8

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

$ActiveCount = @(
    $Report | Where-Object Status -eq "Active"
).Count

$StaleCount = @(
    $Report | Where-Object Status -like "Stale*"
).Count

$NeverSignedInCount = @(
    $Report | Where-Object {
        $_.Status -in @(
            "Never Signed In"
            "Stale - Never Signed In"
        )
    }
).Count

$PendingCount = @(
    $Report | Where-Object Status -eq "Invitation Pending"
).Count

$DisabledCount = @(
    $Report | Where-Object Status -eq "Disabled"
).Count

Write-Host ""
Write-Host "Guest Account Summary"
Write-Host "---------------------"
Write-Host "Total              : $($Report.Count)"
Write-Host "Active             : $ActiveCount"
Write-Host "Stale              : $StaleCount"
Write-Host "Never Signed In    : $NeverSignedInCount"
Write-Host "Invitation Pending : $PendingCount"
Write-Host "Disabled           : $DisabledCount"
Write-Host ""
Write-Host "Stale threshold    : $StaleThreshold days"
Write-Host "Report exported to : $OutputFile"
