# HKCU Registry path
$registryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
$Al = "TaskbarAl"
$Type = "DWORD"  
$Value = "0"
$errMsg = $_.ExceptionMessage

# Shift Start Menu Left
New-ItemProperty -Path $registryPath -Name $Al -Value $Value -PropertyType $Type -Force -ErrorAction SilentlyContinue
Write-Host $errMsg
Write-Output "Remediation Complete"