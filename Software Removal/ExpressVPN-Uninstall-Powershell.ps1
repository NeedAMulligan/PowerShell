$msi = ((Get-Package | Where-Object { $_.Name -like "ExpressVPN" }).fastpackagereference); start-process msiexec.exe -wait -argumentlist  "/x $msi /qn /norestart" 
