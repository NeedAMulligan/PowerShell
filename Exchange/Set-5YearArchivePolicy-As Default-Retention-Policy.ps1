Write-Host "Setting '5YearArchivePolicy' as the default retention policy..."

$policyName = "5YearArchivePolicy"

try {
    # Set the '5YearArchivePolicy' as the default
    Set-RetentionPolicy -Identity $policyName -IsDefault:$true -Confirm:$false
    Write-Host "Successfully set '$policyName' as the default retention policy."

    # Verify the default policy
    $currentDefault = Get-RetentionPolicy | Where-Object {$_.IsDefault -eq $true}
    Write-Host "The new default retention policy is: $($currentDefault.Name)"

    # Re-apply the policy to all existing user mailboxes to ensure consistency.
    # This is important for mailboxes that might still be on the *old* default policy.
    Write-Host "Re-applying '$policyName' to all user mailboxes to ensure consistency."
    Get-Mailbox -Filter { (RecipientTypeDetails -eq 'UserMailbox') } -ResultSize Unlimited | ForEach-Object {
        try {
            # Only set if it's not already assigned, or if it's the old default
            if ($_.RetentionPolicy -ne $policyName) {
                Set-Mailbox -Identity $_.Identity -RetentionPolicy $policyName -Confirm:$false
                Write-Host "Applied '$policyName' to mailbox: $($_.DisplayName)"
            }
        }
        catch {
            Write-Error "Failed to apply '$policyName' to mailbox $($_.DisplayName): $($_.Exception.Message)"
        }
    }

    Write-Host "Initiating Managed Folder Assistant for all user mailboxes to apply policy changes immediately (optional)."
    # This command can be resource-intensive and might not be necessary if you're comfortable waiting.
    Get-Mailbox -ResultSize Unlimited | ForEach-Object {
        try {
            Start-ManagedFolderAssistant -Identity $_.Identity -Confirm:$false
            #Write-Host "Started MFA for mailbox: $($_.DisplayName)" # Uncomment for detailed MFA logging
        }
        catch {
            Write-Error "Failed to start MFA for mailbox $($_.DisplayName): $($_.Exception.Message)"
        }
    }

}
catch {
    Write-Error "An error occurred: $($_.Exception.Message)"
}

Write-Host "Script execution completed."