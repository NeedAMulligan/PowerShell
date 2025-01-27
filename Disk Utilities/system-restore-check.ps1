$check = Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore\" -Name RPSessionInterval

$check1 = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" | Select-Object -ExpandProperty LocalAccountTokenFilterPolicy -ErrorAction silentlycontinue

if($check -match "1") {"System restore is enabled"}

elseif($check -match "0") {Enable-ComputerRestore -Drive C:\}