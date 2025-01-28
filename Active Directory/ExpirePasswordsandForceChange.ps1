Import-Module ActiveDirectory
Get-ADuser -filter * -searchbase "OU=UPDATE-INFO,DC=UPDATE-INFO,DC=net" | Set-ADuser -PasswordNeverExpires:$FALSE -ChangePassWordAtLogon:$TRUE –PassThru
