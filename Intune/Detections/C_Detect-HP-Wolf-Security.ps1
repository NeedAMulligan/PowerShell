$errMsg = $_.ExceptionMessage

# Detect whether HP Wolf Security is installed

if 
(Get-Package | Where-Object {$_.Name -Like "HP Wolf Security"}) {
Write-Host "Not Compliant - HP Wolf Security Installed - Remediation Required"
Write-Host $errMsg
exit 1
}
else {
Write-Host "Compliant - HP Wolf Security not Installed - No Remediation Required"
Write-Host $errMsg
exit 0
}