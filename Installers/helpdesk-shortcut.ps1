$Shell = New-Object -ComObject ("WScript.Shell")
$Shortcut = $Shell.CreateShortcut($Env:ALLUSERSPROFILE + '\Desktop\EWA Helpdesk.lnk')
$Shortcut.TargetPath = "$Env:ProgramFiles\Microsoft Office\root\Office16\OUTLOOK.EXE"
$Shortcut.Arguments = "/c ipm.note /m helpdesk@ewa.com"
$Shortcut.IconLocation = $ShortCut.IconLocation = "C:\Users\Public\Pictures\helpdeskicon.ico"
$ShortCut.Description = 'Submit a ticket to the EWA Helpdesk'
$ShortCut.Save()