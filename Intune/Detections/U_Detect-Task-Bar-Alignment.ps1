$registryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
$Name = "TaskbarAl"
$value = "0"
$errMsg = $_.ExceptionMessage

Try {
    $registry = Get-ItemProperty -Path $registryPath -Name $Name -ErrorAction Stop | Select-Object -ExpandProperty $Name
    If ($Registry -eq $Value){
        Write-Output "Compliant - Task Bar Aligned Left - No Remediation Required"
        Exit 0
    } 
    Write-Warning "Not Compliant - Task Bar Centered - Remediation Required"
    Write-Host $errMsg
    Exit 1
} 
Catch {
    Write-Warning "Not Compliant - Task Bar Centered - Remediation Required"
    Write-Host $errMsg
    Exit 1
}