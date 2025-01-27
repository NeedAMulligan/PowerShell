# HKCU Registry path
$registryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
$LaunchTo = "LaunchTo"
$Type = "DWORD"  
$Value = "1"
$errMsg = $_.ExceptionMessage

# Set File Explorer default view to "This PC" view
New-ItemProperty -Path $registryPath -Name $LaunchTo -Value $Value -PropertyType $Type -Force -ErrorAction SilentlyContinue
Write-Host $errMsg
Write-Output "Remediation Complete"