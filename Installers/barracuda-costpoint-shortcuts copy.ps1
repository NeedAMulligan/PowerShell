# Barracuda
$shortcutPath = $Env:ALLUSERSPROFILE + '\Desktop\Barracuda Spam Filter.url'
$url = 'https://ess.barracudanetworks.com/user/auth/login'
Remove-Item "C:\Users\Public\Desktop\Barracuda Spam Filter.url" -ErrorAction Continue

# Create the shortcut
$shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcutPath)
$shortcut.TargetPath = $url
$shortcut.Save()

# Set desktop icon
Add-Content -Path $shortcutPath -Value "IconFile=C:\Users\Public\Pictures\barracuda2.ico"
Add-Content -Path $shortcutPath -Value "IconIndex=0"

# Costpoint
$shortcutPath = $Env:ALLUSERSPROFILE + '\Desktop\Costpoint.url'
$url = 'https://ewa-cp.costpointenterprise.com/cpweb/'
Remove-Item "C:\Users\Public\Desktop\Costpoint.url" -ErrorAction Continue

# Create the shortcut
$shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcutPath)
$shortcut.TargetPath = $url
$shortcut.Save()

# Set desktop icon
Add-Content -Path $shortcutPath -Value "IconFile=C:\Users\Public\Pictures\costpoint.ico"
Add-Content -Path $shortcutPath -Value "IconIndex=0"