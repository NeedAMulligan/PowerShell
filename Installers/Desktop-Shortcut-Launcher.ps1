#
$Shell = New-Object -ComObject ("WScript.Shell")
$Shortcut = $Shell.CreateShortcut($Env:ALLUSERSPROFILE + '\Desktop\Smart Drive.lnk')
$Shortcut.TargetPath = "$Env:ProgramFiles\internet explorer\iexplore.exe"
$Shortcut.Arguments = 'https://secure.smartdrive.net/login'
$ShortCut.WindowStyle = 3;
$Shortcut.IconLocation = $ShortCut.IconLocation = '\\spc-storage\Apps\Admin Arsenal\PDQ Deploy\Repository\SmartDrive\icons\smartdrive-logo-white-32px.ico'
$ShortCut.Description = 'Smart Drive Web Portal'
$ShortCut.Save()

Remove-Item C:\Users\Public\Desktop\Barracuda Spam Filter.url

$Shell = New-Object -ComObject ("WScript.Shell")
$Shortcut = $Shell.CreateShortcut($Env:ALLUSERSPROFILE + '\Desktop\Costpoint.lnk')
$Shortcut.Arguments = 'https://ewa-cp.costpointenterprise.com/cpweb/'
$Shortcut.IconLocation = 'C:\Users\eberndt\Downloads\costpoint.ico'
$ShortCut.Save()

