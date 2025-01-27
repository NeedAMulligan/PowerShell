# Removes Hp Wolf Security if installed
$errMsg = $_.ExceptionMessage
try{
    Get-Package | Where-Object {$_.Name -Like "HP Wolf Security"} | Uninstall-Package -ErrorAction SilentlyContinue
    Write-Host "Remediation Complete - HP Wolf Security successfully removed!"
    Exit 0

}
catch{
    Write-Error "Remediation Failed - Error removing HP Wolf Security!"
    Write-Host $errMsg
    Exit 1
}