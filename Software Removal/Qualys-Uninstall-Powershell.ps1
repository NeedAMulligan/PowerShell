$msi = ((Get-Package | Where-Object { $_.Name -like "Qualys Cloud Security Agent" }).fastpackagereference); start-process msiexec.exe -wait -argumentlist "/x $msi /qn /norestart"

