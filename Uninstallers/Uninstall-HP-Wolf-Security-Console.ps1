$msi = ((Get-Package | Where-Object { $_.Name -like "*HP Wolf Security - console*" }).fastpackagereference)
start-process msiexec.exe -wait -argumentlist  "/x $msi /qn /norestart"
