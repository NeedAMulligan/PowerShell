$msi = ((Get-Package | Where-Object { $_.Name -like "*HP security update service*" }).fastpackagereference)
start-process msiexec.exe -wait -argumentlist  "/x $msi /qn /norestart"