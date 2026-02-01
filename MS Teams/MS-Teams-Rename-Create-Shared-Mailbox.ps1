# Exit Codes:
# 0: Success. Both the group rename and mailbox creation were successful.
# 1: Failure. An error occurred during the script execution.

$ErrorActionPreference = "Stop"

# --- Configuration ---
$OldGroupName = "Purchases" # The ALIAS/NAME of the existing GroupMailbox/M365 Group
$NewGroupName = "Purchases_OLD" # The new ALIAS for the old group
$NewSharedMailboxName = "Purchases" # The name/alias for the new Shared Mailbox
$SharedMailboxDisplayName = "Purchases"
$SharedMailboxSmtpAddress = "purchases@optechspace.com"

# --- Logging Setup ---
$LogDirectory = "C:\temp"
$TimeStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile = Join-Path -Path $LogDirectory -ChildPath "RenameGroup_CreateSharedMailbox_$TimeStamp.log"

# Create the log directory if it does not exist
if (-not (Test-Path -Path $LogDirectory)) {
    try {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }
    catch {
        Write-Host "Error: Failed to create log directory $LogDirectory. Script stopping."
        exit 1
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [string]$Type = "INFO"
    )
    $LogEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Type] $Message"
    Add-Content -Path $LogFile -Value $LogEntry
}

# --- Main Script Execution ---
try {
    # 1. Rename the existing Microsoft 365 Group
    Write-Log "Attempting to rename existing M365 Group '$OldGroupName' to '$NewGroupName'..."
    
    # CORRECTED: Removed the invalid '-Name' parameter.
    Set-UnifiedGroup -Identity $OldGroupName `
        -DisplayName "$($NewGroupName) - MS Teams" `
        -Alias $NewGroupName `
        -PrimarySmtpAddress "$($NewGroupName)@optechspace.com" `
        -Verbose:$false | Out-Null
    
    Write-Log "SUCCESS: M365 Group renamed. Alias '$OldGroupName' is now free."

    # NOTE: Allow a brief pause for replication to avoid the previous 'object couldn't be found' error.
    Write-Log "Pausing for 10 seconds for directory synchronization..."
    Start-Sleep -Seconds 10
    
    # 2. Create the new Shared Mailbox
    Write-Log "Attempting to create new Shared Mailbox using the freed name '$NewSharedMailboxName'..."
    
    New-Mailbox -Shared `
        -Name $NewSharedMailboxName `
        -DisplayName $SharedMailboxDisplayName `
        -PrimarySmtpAddress $SharedMailboxSmtpAddress `
        -Verbose:$false | Out-Null

    Write-Log "SUCCESS: Shared Mailbox '$SharedMailboxDisplayName' created successfully."
    
    # Successfully completed
    exit 0

}
catch {
    # Handle and log any errors
    $ErrorMessage = $_.Exception.Message
    Write-Log "FAILURE: Script failed during processing." "ERROR"
    Write-Log "Error Details: $ErrorMessage" "ERROR"
    
    # Failure occurred
    exit 1
}
