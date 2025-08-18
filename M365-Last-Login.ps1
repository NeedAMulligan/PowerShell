Connect-MgGraph -Scopes "User.Read.All", "AuditLog.Read.All"

Write-Host "Retrieving all user information, then filtering for licensed users and their last login times. This may take a while for large organizations..."

# Retrieve all users first, including the AssignedLicenses property
# We'll filter locally using Where-Object
$allUsers = Get-MgUser -All -Property DisplayName, UserPrincipalName, SignInActivity, AssignedLicenses

# Filter users who have at least one assigned license
$licensedUsers = $allUsers | Where-Object { $_.AssignedLicenses.Count -gt 0 }

# Create an array to store the results
$results = @()

foreach ($user in $licensedUsers) {
    $lastLogin = $user.SignInActivity.LastSignInDateTime
    $displayName = $user.DisplayName
    $userPrincipalName = $user.UserPrincipalName

    $results += [PSCustomObject]@{
        DisplayName       = $displayName
        UserPrincipalName = $userPrincipalName
        LastSignIn        = if ($lastLogin) { $lastLogin.ToLocalTime() } else { "Never logged in or no recent activity" }
    }
}

# Sort the results by LastSignIn date
$results = $results | Sort-Object LastSignIn -Descending

# Output the results to the console
$results | Format-Table -AutoSize

# Optional: Export the results to a CSV file
$outputPath = "C:\Temp\M365_Licensed_User_Last_Login.csv" # You can change this path
$results | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8

Write-Host "`nScript complete. Results displayed above."
Write-Host "Results also exported to: $outputPath"

# Disconnect from Microsoft Graph
Disconnect-MgGraph