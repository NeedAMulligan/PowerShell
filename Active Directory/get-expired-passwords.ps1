# Get users with expired passwords (excluding disabled accounts)
Get-ADUser -Filter "enabled -eq 'true'" -SearchBase "OU=ewa users,DC=ewacorp,DC=com" -Properties Enabled, PasswordLastSet, PasswordExpired, PasswordNeverExpires | Where-Object{($_.PasswordExpired -eq $True)} | sort Name | ft Name, PasswordLastSet, PasswordExpired, PasswordNeverExpires

# get users with expired passwords by OU
Get-ADUser -Filter * -SearchBase "OU=ewa users,DC=ewacorp,DC=com" -Properties Enabled, PasswordLastSet, PasswordExpired, PasswordNeverExpires | Where-Object{($_.PasswordExpired -eq $True)} | sort Name | ft Name, PasswordLastSet, PasswordExpired, PasswordNeverExpires

# get all users with expired passwords
Get-ADUser -Filter * -Properties Enabled, PasswordLastSet, PasswordExpired, PasswordNeverExpires | Where-Object{($_.PasswordExpired -eq $True)} | sort Name | ft Name, PasswordLastSet, PasswordExpired, PasswordNeverExpires