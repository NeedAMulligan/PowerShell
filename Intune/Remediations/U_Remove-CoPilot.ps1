# Removes Microsoft Copilot if installed
$errMsg = $_.ExceptionMessage

try{
    Get-AppxPackage | Where-Object {$_.Name -Like '*Microsoft.Copilot*'} | Remove-AppxPackage -ErrorAction SilentlyContinue
    Write-Host "Remediation Complete - CoPilot Successfully Removed!"
    Exit 0

}
catch{
    Write-Error "Remediation Failed - Error Removing Copilot!"
    Write-Host $errMsg
    Exit 1
}