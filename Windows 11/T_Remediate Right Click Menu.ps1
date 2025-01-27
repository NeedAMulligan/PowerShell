$registryPath = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"

if((Test-Path $registryPath) -ne $true) {  
New-Item $registryPath -force -erroraction SilentlyContinue };
New-ItemProperty $registryPath -Name '(default)' -Value '' -PropertyType String -Force -erroraction SilentlyContinue;

# Restart Explorer for customizations to take effect
Stop-Process -Name Explorer –Force