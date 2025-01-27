Import-CSV 'C:\users\erikberndt\desktop\ALLADUsers_201707211158(1).csv' |
>> ForEach-Object {Get-ADUser -Filter "DisplayName -eq `"$($_.Name)`"" | Set-ADUser -EmailAddress $_.Email -StreetAddres
s $_.address -City $_.City -PostalCode $_.zip -Title $_."Job Title" -Company $_.Company -OfficePhone $_.Phone -state $_.
State -Department $_.Department}