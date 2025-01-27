#Set the MSI variable
$msi = ((Get-Package | Where-Object { $_.Name -like "*PACKAGE NAME*" }).fastpackagereference)

#Uninstall MSI package
start-process msiexec.exe -wait -argumentlist  "/x $msi /qn /norestart"