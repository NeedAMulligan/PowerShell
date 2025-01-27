$errMsg = $_.ExceptionMessage

# Detect whether New Outlook is installed

if 
(Get-AppxPackage | Where-Object {$_.Name -Like '*OutlookForWindows*'}) {
Write-Host "Not Compliant - Microsoft Outlook (New) Installed - Remediation Required"
Write-Host $errMsg
exit 1
}
else {
Write-Host "Compliant - Microsoft Outlook (New) not Installed - No Remediation Required"
Write-Host $errMsg
exit 0
}