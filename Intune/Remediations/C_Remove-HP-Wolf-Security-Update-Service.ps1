# Removes Hp Security Update Service if installed
$errMsg = $_.ExceptionMessage
try{
    Get-Package | Where-Object {$_.Name -Like "*HP security update service*"} | Uninstall-Package -ErrorAction SilentlyContinue
    Write-Host "Remediation Complete - HP Security Update Service successfully removed!"
    Exit 0

}
catch{
    Write-Error "Remediation Failed - Error removing HP Security Update Service!"
    Write-Host $errMsg
    Exit 1
}