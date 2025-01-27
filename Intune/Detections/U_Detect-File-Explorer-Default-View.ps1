$registryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
$Name = "LaunchTo"
$value = "1"
$errMsg = $_.ExceptionMessage

Try {
    $registry = Get-ItemProperty -Path $registryPath -Name $Name -ErrorAction Stop | Select-Object -ExpandProperty $Name
    If ($Registry -eq $Value){
        Write-Output "Compliant - File Explorer Default View Set - No Remediation Required"
        Exit 0
    } 
    Write-Warning "Not Compliant - File Explorer Default View Not Set - Remediation Required"
    Write-Host $errMsg
    Exit 1
} 
Catch {
    Write-Warning "Not Compliant - File Explorer Default View Not Set - Remediation Required"
    Write-Host $errMsg
    Exit 1
}