# Removes Hp Wolf Security Console if installed

$errMsg = $_.ExceptionMessage
$msi = ((Get-Package | Where-Object { $_.Name -like "HP Wolf Security - Console" }).fastpackagereference)

try{
    Get-Package | Where-Object { $_.Name -like "HP Wolf Security - Console" } | start-process msiexec.exe -wait -argumentlist  "/x $msi /qn /norestart"
    Write-Host "Remediation Complete - HP Wolf Security Console successfully removed!"
    Exit 0

}
catch{
    Write-Error "Remediation Failed - Error removing HP Wolf Security Console!"
    Write-Host $errMsg
    Exit 1
}