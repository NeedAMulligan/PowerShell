$regtaskbar = Get-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name 'TaskbarAl'
$regmenu = Get-ChildItem -Path 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\'

# Orient taskbar to the left

if($regtaskbar -match "0") {Write-Output "Taskbar is left oriented"}

elseif($regtaskbar -match "1") {Set-ItemProperty -Path HKCU:\software\microsoft\windows\currentversion\explorer\advanced -Name 'TaskbarAl' -Type 'DWord' -Value 0 -Force}

# Revert modern right-click menu

if ([string]::IsNullOrWhiteSpace($regmenu)) {
    New-Item -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" -Value "" -Force 
    Write-Output "Modern right click menu not set!"
} 
else {
    Write-Output "Modern right click menu set!"
}

# Restart Explorer for customizations to take effect

Stop-Process -Name Explorer –Force




