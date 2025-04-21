$shortcutPath = $Env:PUBLIC + '\Desktop\Barracuda Message Archiver.url'
$url = 'https://auth.barracudanetworks.com/login/email'
$shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcutPath)
$shortcut.TargetPath = $url
$shortcut.Save()
Add-Content -Path $shortcutPath -Value "IconFile=C:\Users\Public\Pictures\Barracuda-Archiver.ico"
Add-Content -Path $shortcutPath -Value "IconIndex=0"
