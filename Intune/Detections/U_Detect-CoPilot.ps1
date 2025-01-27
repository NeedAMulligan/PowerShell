$errMsg = $_.ExceptionMessage

# Detect whether Microsoft Copilot is installed

if 
(Get-AppxPackage | Where-Object {$_.Name -Like '*Microsoft.Copilot*'}) {
Write-Output "Not Compliant - Copilot Installed - Remediation Required"
Write-Host $errMsg
exit 1
}
else {
Write-Output "Compliant - Copilot Not Installed - No Remediation Required"
Write-Host $errMsg
exit 0
}