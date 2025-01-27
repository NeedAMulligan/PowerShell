# Uninstall Teams Machine Wide Installer
$MachineWide = Get-WmiObject -Class Win32_Product | Where-Object{$_.Name -eq "Teams Machine-Wide Installer"}
$MachineWide
if ($MachineWide){ 
    Write-Output("Start Teams Classic Machine Wide Uninstaller.")
    $MachineWide.Uninstall()}
else {Write-Output("Teams Machine Wide Installer is not present")}

# Uninstall Teams Classic from user profiles
Write-Output("Uninstalling Teams Classic...")
$users = Get-ChildItem C:\Users
Write-Output("List of users: $users")
Write-Output("Uninstall Teams Classic from User Profiles.")
Foreach ($user in $users){
    if (test-path "$($user.fullname)\AppData\Local\Microsoft\Teams\current\Teams.exe") {
        Write-Output("Uninstalling Teams Classic on the following user's profile: ")
        Write-Output($user)
        Start-Process "$($user.fullname)\AppData\Local\Microsoft\Teams\Update.exe" -ArgumentList "--uninstall /s" -PassThru -Wait
        Remove-Item -Path "$($user.fullname)\AppData\Local\Microsoft\Teams" -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Cleanup Desktop Shortcuts
Write-Output("Removing Teams Classic Shortcuts...")
Foreach ($user in $users){
    if (test-path "C:\users\*\Desktop\Microsoft Teams classic.lnk") {
        Write-Output("Remove Teams Classic Shortcut on the following user's desktop: ")
        Write-Output($user)
        Remove-Item -Path "C:\users\*\Desktop\Microsoft Teams classic.lnk" -Verbose -ErrorAction SilentlyContinue
        Remove-Item -Path "C:\users\*\Desktop\Microsoft Teams.lnk" -Verbose -ErrorAction SilentlyContinue
        Remove-Item -Path "C:\users\*\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Microsoft Teams.lnk" -Verbose -ErrorACtion SilentlyContinue
        Remove-Item -Path "C:\users\*\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Microsoft Teams classic.lnk" -Verbose -ErrorAction SilentlyContinue
    }
}

# Remove Teams from localappdata folder
Remove-Item -Path "$($ENV:SystemDrive)\Users\$($_.Name)\AppData\Local\Microsoft\Teams" -Recurse -Force -ErrorAction SilentlyContinue

# Delete registry entries to remove Teams Classic from control panel
$path = "REGISTRY::HKEY_USERS\*\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Teams"

Try {
    $subkeys = Get-ChildItem -Path $path -ErrorAction SilentlyContinue
    foreach ($subkey in $subkeys) {
        Remove-Item -Path $subkey.PSPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Catch {
    Write-Output "Error removing Teams registry entries. Entries may not exist."
}
 
Write-Output("Finished Uninstalling Teams Classic!")