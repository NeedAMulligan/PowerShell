# Remove Costpoint desktop Shortcut
Write-Output("Removing Costpoint Desktop Shortcut...")
    if (test-path "C:\users\*\Desktop\Costpoint.url") {
        Write-Output("Remove Costpoint Desktop Shortcut on the following user's desktop: ")
        Remove-Item -Path "C:\users\*\Desktop\Costpoint.url" -Verbose -ErrorAction SilentlyContinue
}