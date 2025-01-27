$errMsg = $_.ExceptionMessage

# Detect whether Power Automate is installed

if 
(Get-AppxPackage | Where-Object {$_.Name -Like '*PowerAutomate*'}) {
Write-Host "Not Compliant - Microsoft Power Automate Installed - Remediation Required"
Write-Host $errMsg
exit 1
}
else {
Write-Host "Compliant - Microsoft Power Automate not Installed - No Remediation Required"
Write-Host $errMsg
exit 0
}