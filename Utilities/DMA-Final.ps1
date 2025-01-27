Get-WinEvent -FilterHashTable @{ LogName = "microsoft-windows-bitlocker/bitlocker management"; ID = 4122} -maxevents 1 | Format-List;
Confirm-SecureBootUEFI
hostname