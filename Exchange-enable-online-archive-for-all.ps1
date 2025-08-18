# Requires the Exchange Online Management module.
# If you don't have it installed, uncomment the line below and run it:
# Install-Module -Name ExchangeOnlineManagement -Force -AllowClobber

# 1. Connect to Exchange Online PowerShell
Write-Host "Connecting to Exchange Online PowerShell..."
try {
    Connect-ExchangeOnline -ShowBanner:$false
    Write-Host "Successfully connected to Exchange Online."
}
catch {
    Write-Error "Failed to connect to Exchange Online. Please check your credentials and try again. Error: $($_.Exception.Message)"
    exit
}

# 2. Get all user mailboxes that do not have an archive enabled
Write-Host "Retrieving user mailboxes without online archiving enabled..."
try {
    $mailboxesToArchive = Get-Mailbox -ResultSize Unlimited -Filter {ArchiveStatus -Eq "None" -AND RecipientTypeDetails -Eq "UserMailbox"} | Select-Object DisplayName, UserPrincipalName, PrimarySmtpAddress

    if ($mailboxesToArchive.Count -eq 0) {
        Write-Host "No user mailboxes found that are capable of online archiving and do not already have it enabled."
    }
    else {
        Write-Host "Found $($mailboxesToArchive.Count) user mailboxes that will have online archiving enabled."
        Write-Host "Processing mailboxes..."

        foreach ($mailbox in $mailboxesToArchive) {
            Write-Host "Attempting to enable archive for: $($mailbox.UserPrincipalName)..."
            try {
                Enable-Mailbox -Identity $mailbox.UserPrincipalName -Archive -ErrorAction Stop
                Write-Host "Successfully enabled archive for: $($mailbox.UserPrincipalName)"
            }
            catch {
                Write-Warning "Failed to enable archive for $($mailbox.UserPrincipalName). Error: $($_.Exception.Message)"
                # This could be due to licensing issues or other factors.
            }
        }
        Write-Host "Archiving enablement process completed."
    }
}
catch {
    Write-Error "An error occurred while retrieving or processing mailboxes: $($_.Exception.Message)"
}
finally {
    # 3. Disconnect from Exchange Online PowerShell
    Write-Host "Disconnecting from Exchange Online PowerShell."
    Disconnect-ExchangeOnline -Confirm:$false
}