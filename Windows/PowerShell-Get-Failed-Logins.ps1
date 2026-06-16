Get-WinEvent -FilterHashTable @{LogName="Security"; ID=4625} | Select-Object TimeCreated, Message | Format-Table -Wrap
