$errMsg = $_.ExceptionMessage

# Detect whether HP Wolf Security Console is installed

if 
(Get-Package | Where-Object {$_.Name -Like "HP Wolf Security - Console"}) {
Write-Host "Not Compliant - HP Wolf Security Console Installed - Remediation Required"
Write-Host $errMsg
exit 1
}
else {
Write-Host "Compliant - HP Wolf Security Console not Installed - No Remediation Required"
Write-Host $errMsg
exit 0
}