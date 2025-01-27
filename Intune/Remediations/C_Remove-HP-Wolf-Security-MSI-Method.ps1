# Removes HP Wolf Security if installed
$errMsg = $_.ExceptionMessage
$msi = ((Get-Package | Where-Object { $_.Name -like "HP Wolf Security" }).fastpackagereference)
try{
    Get-Package | Where-Object { $_.Name -like "HP Wolf Security" } | start-process msiexec.exe -wait -argumentlist  "/x $msi /qn /norestart"
    Write-Host "Remediation Complete - HP Wolf Security successfully removed!"
    Write-Host $errMsg
    Exit 0

}
catch{
    Write-Error "Remediation Failed - Error removing HP Wolf Security!"
    Write-Host $errMsg
    Exit 1
}