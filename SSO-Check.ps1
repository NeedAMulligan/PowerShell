# Log Path
$connLog = "c:\temp\EntraConnect_Config_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

Import-Module ADSync
$config = Get-ADSyncConnector | Where-Object {$_.Type -eq "Extensible2"}
$config | Select-Object Name, Description | Out-File -FilePath $connLog

# Check if Password Hash Sync is enabled
$globalSettings = Get-ADSyncGlobalSettings
$globalSettings.Parameters | Where-Object {$_.Name -eq "Microsoft.Synchronize.PasswordHash"} | Out-File -FilePath $connLog -Append

Write-Host "Check complete. Review $connLog to see if Password Hash Sync is 'True'." -ForegroundColor Yellow