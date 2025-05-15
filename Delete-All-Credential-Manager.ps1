$cred = cmdkey /list | Select-String "Target:*"
$cred | ForEach-Object { cmdkey /delete:($_ -replace 'Target: ', '') }