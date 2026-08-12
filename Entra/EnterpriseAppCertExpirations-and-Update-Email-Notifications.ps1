# Enterprise Application Certificate Expiration Report
# Reports certificate/key credentials for all service principals.
# Only updates NotificationEmailAddresses for SAML applications.

# 1. Connect to Microsoft Graph
Connect-MgGraph -Scopes "Application.ReadWrite.All"

# 2. Define output path
$outputDir = "C:\temp"

if (-not (Test-Path -Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$outputPath = Join-Path $outputDir "EnterpriseAppCertExpirations.csv"

# 3. Email address to add to SAML application notification settings if missing
$targetEmail = "monitoring@resilientit.us"

# Validate the target email address before making any changes
try {
    [void][System.Net.Mail.MailAddress]::new($targetEmail)
}
catch {
    throw "Invalid target email address: $targetEmail"
}

$report = [System.Collections.Generic.List[PSObject]]::new()

Write-Host "Fetching and processing Enterprise Applications..." -ForegroundColor Cyan

# 4. Retrieve service principals
$servicePrincipals = Get-MgServicePrincipal -All -Property `
    Id,
    DisplayName,
    AppId,
    AppOwnerOrganizationId,
    KeyCredentials,
    NotificationEmailAddresses,
    PreferredSingleSignOnMode,
    ServicePrincipalType

foreach ($sp in $servicePrincipals) {

    $appName  = $sp.DisplayName
    $clientId = $sp.AppId
    $objectId = $sp.Id
    $tenantId = $sp.AppOwnerOrganizationId

    # Normalize existing notification addresses
    $existingEmails = @(
        $sp.NotificationEmailAddresses |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    # NotificationEmailAddresses is only updated for SAML applications
    $isSamlApp = $sp.PreferredSingleSignOnMode -eq "saml"

    if ($isSamlApp) {
        if ($existingEmails -contains $targetEmail) {
            $emailActionStatus = "Unchanged (Already Present)"
        }
        else {
            $updatedEmails = @($existingEmails + $targetEmail)

            try {
                Update-MgServicePrincipal `
                    -ServicePrincipalId $objectId `
                    -NotificationEmailAddresses $updatedEmails `
                    -ErrorAction Stop

                $existingEmails = $updatedEmails
                $emailActionStatus = "Added"

                Write-Host "Added '$targetEmail' to SAML app: $appName" -ForegroundColor Green
            }
            catch {
                $emailActionStatus = "Error Adding Email"

                Write-Warning "Failed to update '$appName' [$objectId]: $($_.Exception.Message)"
            }
        }
    }
    else {
        $emailActionStatus = "Not Applicable (Non-SAML)"
    }

    # Format notification addresses for CSV
    $notificationEmailsString = if ($existingEmails.Count -gt 0) {
        $existingEmails -join "; "
    }
    else {
        "None"
    }

    # 5. Process certificate/key credentials for all service principals
    if ($sp.KeyCredentials -and $sp.KeyCredentials.Count -gt 0) {

        foreach ($cert in $sp.KeyCredentials) {

            $report.Add([PSCustomObject]@{
                ApplicationName       = $appName
                ClientId              = $clientId
                ServicePrincipalId    = $objectId
                HomeTenantId          = $tenantId
                ServicePrincipalType  = $sp.ServicePrincipalType
                SingleSignOnMode      = $sp.PreferredSingleSignOnMode
                CredentialType        = $cert.Type
                CredentialUsage       = $cert.Usage
                CredentialName        = $cert.DisplayName
                KeyId                 = $cert.KeyId
                StartDate             = $cert.StartDateTime
                EndDate               = $cert.EndDateTime
                NotificationEmails    = $notificationEmailsString
                EmailUpdateStatus     = $emailActionStatus
            })
        }
    }
    else {

        $report.Add([PSCustomObject]@{
            ApplicationName       = $appName
            ClientId              = $clientId
            ServicePrincipalId    = $objectId
            HomeTenantId          = $tenantId
            ServicePrincipalType  = $sp.ServicePrincipalType
            SingleSignOnMode      = $sp.PreferredSingleSignOnMode
            CredentialType        = "None / Not Configured"
            CredentialUsage       = $null
            CredentialName        = $null
            KeyId                 = $null
            StartDate             = $null
            EndDate               = $null
            NotificationEmails    = $notificationEmailsString
            EmailUpdateStatus     = $emailActionStatus
        })
    }
}

# 6. Export report
$report |
    Sort-Object EndDate, ApplicationName |
    Export-Csv `
        -Path $outputPath `
        -NoTypeInformation `
        -Encoding UTF8

Write-Host "`nProcess complete! File saved to: $outputPath" -ForegroundColor Cyan
