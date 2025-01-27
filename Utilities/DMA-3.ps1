$tmpfile = "$($env:TEMP)\AllowBuses.reg"
$acl = Get-Acl "HKLM:SYSTEM\CurrentControlSet\Control\DmaSecurity\AllowedBuses"
$person = [System.Security.Principal.NTAccount]"builtin\administrators"          
$access = [System.Security.AccessControl.RegistryRights]"FullControl"
$inheritance = [System.Security.AccessControl.InheritanceFlags]"ContainerInherit,ObjectInherit"
$propagation = [System.Security.AccessControl.PropagationFlags]"None"
$type = [System.Security.AccessControl.AccessControlType]"Allow"
$rule = New-Object System.Security.AccessControl.RegistryAccessRule($person,$access,$inheritance,$propagation,$type)
$acl.AddAccessRule($rule)
$acl |Set-Acl
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
