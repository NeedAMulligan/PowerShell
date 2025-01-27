
# Enable Bitlocker recoery password protector on C: drive - encrypt used space only
Enable-BitLocker C: -RecoveryPasswordProtector -UsedSpaceOnly

# Enable Bitlocker TPM protector on C: drive - encrypt used spaceonly
Enable-BitLocker C: -tpmProtector -UsedSpaceOnly

# Enable Bitlocker 
manage-bde -protectors -enable C:

# Backup Bitlocker recovery key to Entra
BackupToAAD-BitLockerKeyProtector -MountPoint $env:SystemDrive -KeyProtectorId ((Get-BitLockerVolume -MountPoint $env:SystemDrive ).KeyProtector | where {$_.KeyProtectorType -eq "RecoveryPassword" }).KeyProtectorId -WhatIf