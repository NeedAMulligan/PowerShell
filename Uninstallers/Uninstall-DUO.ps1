$msi = ((Get-Package | Where-Object { $_.Name -like "*DUO Authentication*" }).fastpackagereference)
start-process msiexec.exe -wait -argumentlist  "/x $msi /qn /norestart"