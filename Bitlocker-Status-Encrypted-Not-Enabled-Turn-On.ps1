<#
.SYNOPSIS
    Checks BitLocker status on the C: drive and enables it if encrypted but disabled.

.DESCRIPTION
    This script retrieves the BitLocker status for the C: drive.
    - If BitLocker is already 'On', it exits with code 0.
    - If BitLocker is 'Off' but the drive is 100% encrypted, it attempts to enable BitLocker.
      This version assumes that necessary key protectors (e.g., TPM, numerical password) are
      already present on the volume and does not add any new ones.
      If successfully enabled, it exits with code 1.
    - If BitLocker is 'Off' and the drive is not fully encrypted, it exits with code 2.
    - If BitLocker is in any other state (e.g., 'Encrypting', 'Paused'), it exits with code 3.
    - If an error occurs during the process, it exits with code 4.

.OUTPUTS
    Sets an exit code indicating the BitLocker status or action taken.
    No direct console output for silent operation.

.NOTES
    Requires administrator privileges to run.
    Ensure you have the BitLocker PowerShell cmdlets installed (usually part of Windows).
    This version relies on existing key protectors for BitLocker activation.
#>

# Define exit codes
$exitCodeBitLockerOn = 0
$exitCodeBitLockerEnabled = 1
$exitCodeBitLockerOffNotEncrypted = 2
$exitCodeBitLockerOtherState = 3
$exitCodeError = 4

# Function to set the exit code and exit the script
function Set-ExitCode {
    param (
        [int]$Code,
        [string]$Message = "" # Message parameter is kept for consistency but will not be used for console output
    )
    # This function now only sets the exit code silently.
    $LASTEXITCODE = $Code
    exit $Code
}

try {
    # Get BitLocker volume information for the C: drive
    $bitLockerVolume = Get-BitLockerVolume -MountPoint "C:" -ErrorAction Stop

    if ($bitLockerVolume) {
        $protectionStatus = $bitLockerVolume.ProtectionStatus
        $encryptionPercentage = $bitLockerVolume.EncryptionPercentage

        if ($protectionStatus -eq "On") {
            Set-ExitCode $exitCodeBitLockerOn
        }
        elseif ($protectionStatus -eq "Off" -and $encryptionPercentage -eq 100) {
            # BitLocker is currently OFF but the drive is 100% encrypted. Attempting to enable BitLocker...

            try {
                # Enable BitLocker without adding new protectors.
                # This assumes existing protectors (e.g., TPM, numerical password) are already in place.
                Enable-BitLocker -MountPoint "C:" -ErrorAction Stop

                # Verify status after attempting to enable
                $updatedBitLockerVolume = Get-BitLockerVolume -MountPoint "C:"
                if ($updatedBitLockerVolume.ProtectionStatus -eq "On") {
                    Set-ExitCode $exitCodeBitLockerEnabled
                } else {
                    Set-ExitCode $exitCodeError # Failed to confirm 'On' status after attempt
                }
            }
            catch {
                Set-ExitCode $exitCodeError # Failed to enable BitLocker
            }
        }
        elseif ($protectionStatus -eq "Off" -and $encryptionPercentage -lt 100) {
            Set-ExitCode $exitCodeBitLockerOffNotEncrypted
        }
        else {
            Set-ExitCode $exitCodeBitLockerOtherState
        }
    }
    else {
        Set-ExitCode $exitCodeError # Could not retrieve BitLocker status
    }
}
catch {
    Set-ExitCode $exitCodeError # An unexpected error occurred
}
