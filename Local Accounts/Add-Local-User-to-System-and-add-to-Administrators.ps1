New-LocalUser "lcadmn2024" -Password (ConvertTo-SecureString "PASSWORD" -AsPlainText -force) –PasswordNeverExpires
Add-LocalGroupMember -Group Administrators -Member "lcadmn2024"
Set-LocalUser -Name "lcadmn2024" -PasswordNeverExpires 1