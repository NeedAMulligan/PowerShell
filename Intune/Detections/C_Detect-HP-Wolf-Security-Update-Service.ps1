$errMsg = $_.ExceptionMessage

# Detect whether HP Security Update Service is installed

if 
(Get-Package | Where-Object {$_.Name -Like "HP security update service"}) {
Write-Host "Not Compliant - HP Security Update Service - Remediation Required"
Write-Host $errMsg
exit 1
}
else {
Write-Host "Compliant - HP Security Update Service - No Remediation Required"
Write-Host $errMsg
exit 0
}