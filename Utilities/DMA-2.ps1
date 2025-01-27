$tmpfile = "$($env:TEMP)\AllowBuses.reg"
$acl = Get-Acl 'HKLM:SYSTEM\CurrentControlSet\Control\DmaSecurity\AllowedBuses'
$acl.Access
$idRef = [System.Security.Principal.NTAccount]("ewacorp.com\eberndt-da")
$regRights = [System.Security.AccessControl.RegistryRights]::FullControl
$inhFlags = [System.Security.AccessControl.InheritanceFlags]::None
$prFlags = [System.Security.AccessControl.PropagationFlags]::None
$acType = [System.Security.AccessControl.AccessControlType]::Allow
$rule = New-Object System.Security.AccessControl.RegistryAccessRule ($idRef, $regRights, $inhFlags, $prFlags, $acType)
$acl | Set-Acl -Path 'HKLM:SYSTEM\CurrentControlSet\Control\DmaSecurity\AllowedBuses'
'Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\DmaSecurity\AllowedBuses]'`
| Out-File $tmpfile
(Get-PnPDevice -InstanceId PCI* `
| Format-Table -Property FriendlyName,InstanceId -HideTableHeaders -AutoSize `
| Out-String -Width 300).trim() `
-split "`r`n" `
-replace '&SUBSYS.*', '' `
-replace '\s+PCI\\', '"="PCI\\' `
| Foreach-Object{ "{0}{1}{2}" -f '"',$_,'"' } `
| Out-File $tmpfile -Append
regedit /s $tmpfile
reg import $tmpfile
