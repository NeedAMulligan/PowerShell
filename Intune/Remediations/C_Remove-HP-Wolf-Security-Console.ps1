# Removes Hp Wolf Security Console if installed
$errMsg = $_.ExceptionMessage
try{
    Get-Package | Where-Object {$_.Name -Like "HP Wolf Security - Console"} | Uninstall-Package -ErrorAction SilentlyContinue
    Write-Host "Remediation Complete - HP Wolf Security Console successfully removed!"
    Exit 0

}
catch{
    Write-Error "Remediation Failed - Error removing HP Wolf Security Console!"
    Write-Host $errMsg
    Exit 1
}