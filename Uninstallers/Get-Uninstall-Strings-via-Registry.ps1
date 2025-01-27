$app = '*7-Zip*'
Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | 
Where-Object {$_.DisplayName -like $app} | Select-Object -Property DisplayName, UninstallString