# Removes Dev Home App if installed
$errMsg = $_.ExceptionMessage
try{
    Get-AppxPackage | Where-Object {$_.Name -Like '*DevHome*'} | Remove-AppxPackage -ErrorAction SilentlyContinue
    Write-Host "Remediation Complete - Dev Home successfully removed!"
    Exit 0

}
catch{
    Write-Error "Remediation Failed - Error removing Dev Home!"
    Write-Host $errMsg
    Exit 1
}