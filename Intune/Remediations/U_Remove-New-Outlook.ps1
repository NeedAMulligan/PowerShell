# Removes Outlook (New) if installed
$errMsg = $_.ExceptionMessage
try{
    Get-AppxPackage | Where-Object {$_.Name -Like '*OutlookForWindows*'} | Remove-AppxPackage -ErrorAction SilentlyContinue
    Write-Host "Remediation Complete - Microsoft Outlook (New) successfully removed!"
    Exit 0
}
catch{
    Write-Error "Remediation Failed - Error removing Microsoft Outlook (New)!"
    Write-Host $errMsg
    Exit 1
}