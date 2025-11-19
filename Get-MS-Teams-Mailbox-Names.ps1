# Exit Code Explanations:
# 0: Script executed successfully.
# 1: Failed to retrieve or export the data due to an unexpected error.

#region Initialization and Logging
$LogPath = "C:\Temp"
$LogFileName = "Get-TeamsMailboxNames_Connected_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$LogFile = Join-Path -Path $LogPath -ChildPath $LogFileName
$OutputFileName = "TeamsMailboxNames_Connected_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$OutputFile = Join-Path -Path $LogPath -ChildPath $OutputFileName
$ExitCode = 0

# Function to write to log file
function Write-Log {
    param([Parameter(Mandatory=$true)][string]$Message)
    try {
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message" | Out-File -FilePath $LogFile -Append -Force
    }
    catch {} # Suppress errors during logging to keep the script silent
}

Write-Log -Message "Script started (assuming pre-existing Exchange Online session)."
Write-Log -Message "Output CSV file: $OutputFile"
#endregion

#region Get Teams Mailboxes and Export
try {
    Write-Log -Message "Retrieving Teams Mailbox Names (Unified Groups with a Team)..."

    # Get Unified Groups (Microsoft 365 Groups) that have a Team
    # The 'ResourceProvisioningOptions -eq "Team"' filters groups associated with a Team.
    $TeamsMailboxes = Get-UnifiedGroup -Filter { ResourceProvisioningOptions -eq "Team" } -ResultSize Unlimited -ErrorAction Stop |
        Select-Object DisplayName, PrimarySmtpAddress, WhenCreated

    if ($TeamsMailboxes) {
        # Export the data to the CSV file
        $TeamsMailboxes | Export-Csv -Path $OutputFile -NoTypeInformation -Force
        $Count = $TeamsMailboxes.Count
        Write-Log -Message "SUCCESS: Found $Count Teams mailboxes. Data exported to $OutputFile"
    }
    else {
        Write-Log -Message "WARNING: No Teams mailboxes found matching the criteria."
        # Create an empty file to indicate successful execution but no data
        "" | Out-File -FilePath $OutputFile -Force
    }
}
catch {
    $ErrorMessage = $_.Exception.Message
    Write-Log -Message "ERROR: Failed during data retrieval and export. Details: $ErrorMessage"
    $ExitCode = 1 # Unexpected error
}
#endregion

Write-Log -Message "Script finished with exit code $ExitCode."
exit $ExitCode