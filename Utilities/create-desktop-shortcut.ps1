$WshShell = New-Object -comObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("C:\users\USERNAME\Desktop\WinDirStat.lnk")
$Shortcut.TargetPath = "C:\Program Files (x86)\WinDirStat\windirstat.exe"
$Shortcut.Save()