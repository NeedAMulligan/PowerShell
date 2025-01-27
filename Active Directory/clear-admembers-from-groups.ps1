get-aduser -filter * -searchbase "OU=2023,OU=Disabled Users,DC=ewacorp,DC=com" -properties MemberOf
 | ForEach-Object { $_.MemberOf | Remove-ADGroupMember -Members $_.DistinguishedName -verbose -WhatIf 
}
