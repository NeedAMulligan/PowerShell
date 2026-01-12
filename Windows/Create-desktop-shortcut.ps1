$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut("C:\temp\shortcut.lnk")
$shortcut.TargetPath = "C:\Windows\System32\cmd.exe"
$shortcut.Save()
