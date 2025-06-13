# Requires the Exchange Online Management module
# Install-Module -Name ExchangeOnlineManagement -Scope CurrentUser -Force # Uncomment to install if needed

Import-Module ExchangeOnlineManagement

# Define the export path
$exportPath = "C:\temp\"

# Create the directory if it doesn't exist
if (-not (Test-Path $exportPath)) {
    New-Item -Path $exportPath -ItemType Directory -Force
}

# Generate a dynamic filename with a timestamp
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$fileName = "SharedMailboxGUIDs_$timestamp.csv"
$fullExportPath = Join-Path -Path $exportPath -ChildPath $fileName

Write-Host "Connecting to Exchange Online..."
try {
    Connect-ExchangeOnline -UserPrincipalName your.admin.account@yourdomain.com -ShowProgress $true
}
catch {
    Write-Error "Failed to connect to Exchange Online. Please check your credentials and network connection. Error: $($_.Exception.Message)"
    exit
}

Write-Host "Retrieving all shared mailboxes. This may take a moment..."
$sharedMailboxes = @()
try {
    # Get all mailboxes that are shared (RecipientTypeDetails -eq "SharedMailbox")
    # Select desired properties to reduce memory usage and improve performance
    $sharedMailboxes = Get-Mailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited |
                       Select-Object DisplayName, PrimarySmtpAddress, Alias, ExchangeGUID, ExternalDirectoryObjectId, WhenCreated, WhenChanged

    if ($sharedMailboxes.Count -gt 0) {
        Write-Host "Found $($sharedMailboxes.Count) shared mailboxes."
        Write-Host "Exporting data to '$fullExportPath'..."
        $sharedMailboxes | Export-Csv -Path $fullExportPath -NoTypeInformation -Encoding UTF8

        Write-Host "Export complete!"
        Write-Host "You can find the CSV file at: $fullExportPath"
    } else {
        Write-Warning "No shared mailboxes found in your Exchange Online organization."
    }
}
catch {
    Write-Error "An error occurred while retrieving or exporting shared mailbox data: $($_.Exception.Message)"
}
finally {
    Write-Host "Disconnecting from Exchange Online..."
    Disconnect-ExchangeOnline
}