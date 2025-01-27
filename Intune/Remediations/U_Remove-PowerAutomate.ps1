# Removes Power Automate if installed
$errMsg = $_.ExceptionMessage
try{
    Get-AppxPackage | Where-Object {$_.Name -Like '*PowerAutomate*'} | Remove-AppxPackage -ErrorAction SilentlyContinue
    Write-Host "Remediation Complete - Power Automate successfully removed!"
    Write-Host $errMsg
    Exit 0

}
catch{
    Write-Error "Remediation Failed - Error removing Power Automate!"
    Write-Host $errMsg
    Exit 1
}