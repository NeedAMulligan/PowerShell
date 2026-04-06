$key = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy"
if (!(Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
Set-ItemProperty -Path $key -Name "01" -Type DWord -Value 1

Set-ItemProperty -Path $key -Name "2048" -Type DWord -Value 7

Set-ItemProperty -Path $key -Name "04" -Type DWord -Value 1
