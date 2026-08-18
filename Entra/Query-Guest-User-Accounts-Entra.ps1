# Requires Microsoft.Graph module
# Install-Module Microsoft.Graph -Scope CurrentUser

$OutputFolder = "C:\Temp"

if (-not (Test-Path $OutputFolder)) {
    New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
}

$Timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$OutputFile = Join-Path $OutputFolder "M365_GuestAccounts_$Timestamp.csv"

# Connect to Microsoft Graph
Connect-MgGraph -Scopes "User.Read.All"

# Query guest users
$GuestUsers = Get-MgUser `
    -Filter "userType eq 'Guest'" `
    -All `
    -Property Id,DisplayName,UserPrincipalName,Mail,AccountEnabled,CreatedDateTime,ExternalUserState,ExternalUserStateChangeDateTime

# Select useful fields
$Report = $GuestUsers | Select-Object `
    DisplayName,
    UserPrincipalName,
    Mail,
    AccountEnabled,
    CreatedDateTime,
    ExternalUserState,
    ExternalUserStateChangeDateTime,
    Id

# Display results
$Report | Format-Table -AutoSize

# Export results
$Report | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8

Write-Host "Guest account report exported to: $OutputFile"
