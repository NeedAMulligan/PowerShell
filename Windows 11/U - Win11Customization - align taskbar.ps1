# HKCU Registry path
$registryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
# Shift Start Menu Left
$Al = "TaskbarAl"  
$value = "0"

New-ItemProperty -Path $registryPath -Name $Al -Value $value -PropertyType DWORD -Force -ErrorAction Ignore