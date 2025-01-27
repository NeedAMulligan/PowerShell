# Removes HP Security Update Service if installed

$errMsg = $_.ExceptionMessage
$msi = ((Get-Package | Where-Object { $_.Name -like "HP Security Update Service" }).fastpackagereference)

try{
    Get-Package | Where-Object { $_.Name -like "HP Security Update Service" } | start-process msiexec -wait -argumentlist  "/x $msi /qn /norestart"
    Write-Host "Remediation Complete - HP Security Update Service successfully removed!"
    Exit 0

}
catch{
    Write-Error "Remediation Failed - Error removing HP Security Update Service!"
    Write-Host $errMsg
    Exit 1
}