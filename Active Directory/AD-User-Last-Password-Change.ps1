Get-ADUser -filter * -searchbase "OU=UPDATE-INFO,OU=UPDATE-INFO,DC=UPDATE-INFO,DC=net" -properties passwordlastset, passwordneverexpires, CanonicalName | sort-object name, CanonicalName | select-object Name, CanonicalName, passwordlastset, passwordneverexpires | Export-csv -path c:\temp\UPDATE-INFO.csv
Start-Sleep -s 5
Get-ChildItem -Filter C:\temp\*.csv | Select-Object -ExpandProperty FullName | Import-Csv | Export-Csv c:\temp\merged.csv -NoTypeInformation -Append
