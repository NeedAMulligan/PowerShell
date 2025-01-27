$errMsg = $_.ExceptionMessage

# Detect whether Dev Home is installed

if 
(Get-AppxPackage | Where-Object {$_.Name -Like '*DevHome*'}) {
Write-Output "Not Compliant - Dev Home Installed - Remediation Required"
Write-Host $errMsg
exit 1
}
else {
Write-Output "Compliant - Dev Home not Installed - No Remediation Required"
Write-Host $errMsg
exit 0
}