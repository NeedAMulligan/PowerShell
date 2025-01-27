// Get last login time of domain user
ImportModule ActiveDirectory
$Path = 'C:\LastLogon.csv' 
Get-ADUser -Filter {enabled -eq $true} -Properties LastLogonTimeStamp | Select-Object Name,@{Name="Stamp"; Expression={[DateTime]::FromFileTime($_.lastLogonTimestamp).ToString('yyyy-MM-dd_hh:mm:ss')}} | Export-Csv -Path $Path –notypeinformation