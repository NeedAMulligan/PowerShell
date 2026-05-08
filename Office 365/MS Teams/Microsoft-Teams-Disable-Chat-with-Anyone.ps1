<#
.SYNOPSIS
Disables the Microsoft Teams feature "Chat with anyone who has an email address" (Roadmap ID 513271).
.DESCRIPTION
This script sets the 'UseB2BInvitesToAddExternalUsers' parameter to $false on the Global Teams Messaging Policy, 
effectively disabling the ability for users to start 1:1 chats with external individuals via their email address.

The script is designed for silent execution, creates a dynamic log file, and uses PowerShell.
It assumes the Microsoft Teams PowerShell Module is installed and the session is already connected to Microsoft Teams 
(e.g., via Connect-MicrosoftTeams).

.NOTES
Exit Codes and Explanations:
Exit Code 0: Success - Policy updated successfully and verification passed.
Exit Code 1: Failure - An unhandled exception or verification error occurred (e.g., module not found, no connection, permission denied).
#>

# --- User Configuration ---
$PolicyIdentity = "Global" # Targeting the Global Teams Messaging Policy
$FeatureName = "Teams Chat with External Email (Roadmap ID 513271)"
# Create a log file saved to c:\temp using a dynamic name
$LogPath = "C:\temp\Teams_Disable_B2BInvite_$(Get-Date -Format "yyyyMMdd_HHmmss").log"
# --------------------------

# Ensure the script is completely silent with no user interaction or output.
# All operational details are captured in the log file via Start-Transcript.
Start-Transcript -Path $LogPath -Force
$ErrorActionPreference = "Stop" # Halt script execution on non-terminating errors

try {
    # Attempt to load the Teams module silently, if not already loaded.
    Write-Output "Checking and importing MicrosoftTeams module..."
    if (-not (Get-Module -Name "MicrosoftTeams")) {
        Import-Module MicrosoftTeams -Force -ErrorAction SilentlyContinue
    }
    
    # 1. Perform the action: Disable the feature
    Write-Output "Attempting to disable feature: '$FeatureName' on policy '$PolicyIdentity'."
    Set-CsTeamsMessagingPolicy -Identity $PolicyIdentity -UseB2BInvitesToAddExternalUsers $false -ErrorAction Stop
    Write-Output "Policy update command executed successfully."
    
    # 2. Verification step
    $policyCheck = Get-CsTeamsMessagingPolicy -Identity $PolicyIdentity
    if ($policyCheck.UseB2BInvitesToAddExternalUsers -eq $false) {
        Write-Output "Verification successful: UseB2BInvitesToAddExternalUsers is set to False."
        Stop-Transcript
        exit 0 # Success
    } else {
        Write-Output "Verification FAILED: UseB2BInvitesToAddExternalUsers is NOT set to False."
        Stop-Transcript
        exit 1 # Failure
    }

} catch {
    # Log any unhandled exceptions
    Write-Output "An unhandled exception occurred:"
    Write-Output $_.Exception.Message
    
    Stop-Transcript
    exit 1 # Failure
}
