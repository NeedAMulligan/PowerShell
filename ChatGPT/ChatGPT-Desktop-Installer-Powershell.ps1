# Get the installation path of the existing App Installer bundle
$AppxManifest = Get-AppxPackage -AllUsers -Name "Microsoft.DesktopAppInstaller" | 
                Where-Object {$_.InstallLocation -ne $null} | 
                Select-Object -Last 1

if ($AppxManifest) {
    cd $AppxManifest.InstallLocation
    # Directly call the winget executable from its local system path
    .\winget.exe install --id=9NT1R1C2HH7J --source=msstore --accept-package-agreements --accept-source-agreements --silent
} else {
    Write-Error "App Installer files not found on this machine."
}
