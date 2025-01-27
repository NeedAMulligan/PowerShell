# Removes Quick Assist App if installed
$errMsg = $_.ExceptionMessage
try{
    Get-AppxPackage | Where-Object {$_.Name -Like '*QuickAssist*'} | Remove-AppxPackage -ErrorAction SilentlyContinue
    Write-Host "Remediation Complete - Quick Assist successfully removed!"
    exit 0

}
catch{
    Write-Error "Remediation Failed - Error removing Quick Assist!"
    Write-Host $errMsg
    Exit 1
}