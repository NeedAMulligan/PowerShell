Import-Module ActiveDirectory
Get-ADuser -filter * -searchbase "OU=Superior Paving Employees,DC=superiorpaving,DC=net" | Set-ADuser -PasswordNeverExpires:$FALSE -ChangePassWordAtLogon:$TRUE –PassThru