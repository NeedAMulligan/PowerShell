# HKCU Registry path
$registryPath = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"

# Revert to classic context menu  
$value = ""

# Set registry value
New-Item -Path $registryPath -Value $value -Force -ErrorAction Ignore

# Restart Explorer for customizations to take effect
Stop-Process -Name Explorer –Force