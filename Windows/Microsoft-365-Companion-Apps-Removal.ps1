# Intune / SCCM Remediation Script for Microsoft 365 Companion Apps
$PackageName = "Microsoft.M365Companions"

# 1. Terminate running M365 Companion processes
Get-Process -Name "*M365Companion*", "*PeopleCompanion*", "*FileSearchCompanion*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# 2. Remove package from ALL active user profiles
$UserPackages = Get-AppxPackage -AllUsers -Name $PackageName -ErrorAction SilentlyContinue
if ($UserPackages) {
    foreach ($Pkg in $UserPackages) {
        Write-Output "Removing $PackageName for profile: $($Pkg.PackageUserInformation)"
        Remove-AppxPackage -Package $Pkg.PackageFullName -AllUsers -ErrorAction SilentlyContinue
    }
}

# 3. Remove provisioned package (prevents auto-installation on new user logins)
$ProvisionedPackage = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq $PackageName }
if ($ProvisionedPackage) {
    Write-Output "Removing provisioned package: $($ProvisionedPackage.DisplayName)"
    Remove-AppxProvisionedPackage -Online -PackageName $ProvisionedPackage.PackageName -ErrorAction SilentlyContinue
}

# 4. Cleanup offline user registry hives (captures inactive/logged-off profiles)
$UserProfiles = Get-CimInstance Win32_UserProfile | Where-Object { !$_.Special -and !$_.Loaded }

foreach ($Profile in $UserProfiles) {
    $HivePath = "$($Profile.LocalPath)\NTUSER.DAT"
    if (Test-Path $HivePath) {
        $MountedKey = "HKU\Temp_$($Profile.SID)"
        reg load $MountedKey $HivePath 2>$null
        
        $AppXReg = "Registry::$MountedKey\Software\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Applications"
        Get-ChildItem -Path $AppXReg -ErrorAction SilentlyContinue | 
            Where-Object { $_.PSChildName -like "*$PackageName*" } | 
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            
        [gc]::Collect()
        reg unload $MountedKey 2>$null
    }
}

Write-Output "Remediation completed for $PackageName."