# Requires Administrator privileges to run
# This script runs silently and saves the recovery password to a file,
# communicating its status via exit codes.

# Define custom exit codes for clarity
$ExitCode_Success = 0
$ExitCode_EnableBitLocker_Failed = 1
$ExitCode_RecoveryFile_Failed = 2
$ExitCode_Already_Encrypted = 3
$ExitCode_Drive_Not_Found_Or_Cmdlets_Missing = 4
$ExitCode_Unexpected_Status = 5

# Initialize the exit code to success; it will be updated if an issue occurs.
$LASTEXITCODE = $ExitCode_Success

$driveLetter = "C:"
$recoveryKeyFilePath = "C:\BitLocker_Recovery\BitLockerRecoveryPassword_C_Drive.txt"

# --- Step 1: Ensure the recovery key directory exists ---
# This block attempts to create the directory for storing the recovery password.
# If it fails, an exit code is set, and the script terminates.
try {
    # Check if the parent directory for the recovery key file exists.
    if (-not (Test-Path (Split-Path $recoveryKeyFilePath -Parent))) {
        # Create the directory if it doesn't exist. Output is suppressed with Out-Null.
        New-Item -ItemType Directory -Path (Split-Path $recoveryKeyFilePath -Parent) -Force | Out-Null
    }
} catch {
    # If directory creation fails, set the appropriate exit code and exit.
    $LASTEXITCODE = $ExitCode_RecoveryFile_Failed
    exit $LASTEXITCODE
}

# --- Step 2: Get the current BitLocker status of the C: drive ---
# This block attempts to retrieve the BitLocker status.
# If the drive isn't found or cmdlets are missing, an exit code is set, and the script terminates.
try {
    # Get-BitLockerVolume is used to check the encryption status.
    # -ErrorAction SilentlyContinue prevents errors from being displayed on console.
    $bitlockerStatus = Get-BitLockerVolume -MountPoint $driveLetter -ErrorAction SilentlyContinue
} catch {
    # This catch block handles errors encountered while *trying* to get the status,
    # rather than errors related to the status itself (e.g., cmdlets not found).
    $LASTEXITCODE = $ExitCode_Drive_Not_Found_Or_Cmdlets_Missing
    exit $LASTEXITCODE
}

# Check if $bitlockerStatus is null, indicating the drive wasn't found or cmdlets are truly absent.
if ($null -eq $bitlockerStatus) {
    $LASTEXITCODE = $ExitCode_Drive_Not_Found_Or_Cmdlets_Missing
    exit $LASTEXITCODE
}

# --- Step 3: Process based on the retrieved BitLocker status ---
# This conditional block determines the next action based on the drive's current encryption state.
if ($bitlockerStatus.VolumeStatus -eq "FullyDecrypted" -or $bitlockerStatus.VolumeStatus -eq "EncryptionPaused") {
    # If the drive is decrypted or encryption is paused, proceed to enable BitLocker.
    try {
        # Enable BitLocker with specified parameters:
        # -EncryptionMethod XtsAes256: Uses strong AES 256-bit encryption with XTS mode.
        # -UsedSpaceOnly: Encrypts only the currently used space, speeding up the initial process.
        # -TpmProtector: Uses the Trusted Platform Module for protection.
        # -RecoveryPassword: Generates a new recovery password.
        # -Confirm:$false: Suppresses the confirmation prompt, ensuring silent operation.
        # -ErrorAction Stop: Ensures any error during Enable-BitLocker is caught by the 'catch' block.
        $bitlockerOutput = Enable-BitLocker -MountPoint $driveLetter `
                               -EncryptionMethod XtsAes256 `
                               -UsedSpaceOnly `
                               -TpmProtector `
                               -RecoveryPassword `
                               -Confirm:$false `
                               -ErrorAction Stop

        # Save the generated recovery password to the specified file.
        if ($bitlockerOutput -and $bitlockerOutput.RecoveryPassword) {
            try {
                $bitlockerOutput.RecoveryPassword | Set-Content -Path $recoveryKeyFilePath -Force
            } catch {
                # If writing the recovery file fails, set the appropriate exit code and exit.
                $LASTEXITCODE = $ExitCode_RecoveryFile_Failed
                exit $LASTEXITCODE
            }
        }
        # If BitLocker initiation is successful and password saved, set success exit code.
        $LASTEXITCODE = $ExitCode_Success

    } catch {
        # If any error occurs during the Enable-BitLocker command, set the failure exit code.
        $LASTEXITCODE = $ExitCode_EnableBitLocker_Failed
        exit $LASTEXITCODE
    }
} elseif ($bitlockerStatus.VolumeStatus -eq "FullyEncrypted") {
    # If the drive is already fully encrypted, set the corresponding exit code.
    $LASTEXITCODE = $ExitCode_Already_Encrypted
} else {
    # For any other unexpected BitLocker volume status, set a specific exit code.
    $LASTEXITCODE = $ExitCode_Unexpected_Status
}

# --- Step 4: Exit the script with the determined status code ---
# This ensures that the calling process can retrieve the exit code.
exit $LASTEXITCODE
