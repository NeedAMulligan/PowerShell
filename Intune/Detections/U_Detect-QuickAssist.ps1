$errMsg = $_.ExceptionMessage

# Detect whether Quick Assist is installed

if 
(Get-AppxPackage | Where-Object {$_.Name -Like '*QuickAssist*'}) {
Write-Host "Not Compliant - Microsoft Quick Assist Installed - Remediation Required"
Write-Host $errMsg
exit 1
}
else {
Write-Host "Compliant - Microsoft Quick Assist not Installed - No Remediation Required"
Write-Host $errMsg
exit 0
}