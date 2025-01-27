$tmpfile = "$($env:TEMP)\Buses.txt"
$tmpfile2 = "$($env:TEMP)\Buses-2.txt"
$tmpfile3 = "$($env:TEMP)\Buses-3.txt"
Out-File $tmpfile
(Get-WinEvent -FilterHashTable @{ LogName = "microsoft-windows-bitlocker/bitlocker management"; ID = 4122} -maxevents 1 | Format-List `
| Format-Table -Property FriendlyName,InstanceId `
| Out-String -Width 300).trim() `
-split "`r`n" `
-replace '&SUBSYS.*', '' `
-replace '\s+PCI\\', '"="PCI\\' `
| Foreach-Object{ "{0}{1}{2}" -f '"',$_,'"' } `
| Out-File $tmpfile -Append
regedit /s $tmpfile
#Select-String "PCI*" $tmpfile | Foreach {$_.Line} > $tmpfile2
#(Get-Content -path $tmpfile2 -raw) | Foreach-Object {
$_.replace('"', '').replace('=', '')
} | Set-Content -Path $tmpfile3

Confirm-SecureBootUEFI
hostname