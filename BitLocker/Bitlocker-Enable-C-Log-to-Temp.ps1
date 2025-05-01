# Ensure the log directory exists
$logPath = "C:\Temp"
$logFile = "$logPath\bitlocker-results.txt"

if (!(Test-Path -Path $logPath)) {
    New-Item -Path $logPath -ItemType Directory -Force
}

# Start transcript logging
Start-Transcript -Path $logFile -Append

Write-Output "==== BitLocker Status Script Started: $(Get-Date) ===="

# Step 1: Enable BitLocker on the C: drive if not already enabled
$bitlockerStatus = Get-BitLockerVolume -MountPoint "C:"

if ($bitlockerStatus.ProtectionStatus -eq 0) {
    Write-Output "BitLocker is not enabled on C:. Enabling BitLocker..."

    # Add a recovery password protector
    $secureProtector = Add-BitLockerKeyProtector -MountPoint "C:" -RecoveryPasswordProtector

    # Enable BitLocker with TPM + Recovery Password
    Enable-BitLocker -MountPoint "C:" -EncryptionMethod XtsAes256 -RecoveryPasswordProtector -UsedSpaceOnly -TpmProtector

    Write-Output "BitLocker encryption initiated on C:. It may take some time to complete."
} else {
    Write-Output "BitLocker is already enabled on C:. Proceeding to check protection status..."
}

# Wait briefly to allow BitLocker status to update
Start-Sleep -Seconds 5

# Step 2: Re-check BitLocker status
$bitlockerStatus = Get-BitLockerVolume -MountPoint "C:"
$volumeStatus = $bitlockerStatus.VolumeStatus
$protectionStatus = $bitlockerStatus.ProtectionStatus

# Interpret protection status
switch ($protectionStatus) {
    0 { $protectionState = "Off" }
    1 { $protectionState = "On" }
    default { $protectionState = "Unknown" }
}

Write-Output "BitLocker Volume Status for C: drive: $volumeStatus"
Write-Output "BitLocker Protection is: $protectionState"

# Step 3: Backup recovery key to AD if protection is On
if ($protectionStatus -eq 1) {
    Write-Output "BitLocker protection is On. Attempting to backup key to Active Directory..."

    $keyProtectors = $bitlockerStatus.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }

    foreach ($protector in $keyProtectors) {
        try {
            Backup-BitLockerKeyProtector -MountPoint "C:" -KeyProtectorId $protector.KeyProtectorId
            Write-Output "Recovery key successfully backed up to Active Directory."
        } catch {
            Write-Error "Failed to back up recovery key to Active Directory: $_"
        }
    }
} else {
    Write-Warning "BitLocker protection is not On. No key backup attempted."
    Stop-Transcript
    exit 1
}

Write-Output "==== BitLocker Script Completed Successfully: $(Get-Date) ===="

# Stop logging
Stop-Transcript
exit 0
