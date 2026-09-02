# Establish C:\Temp directory and dynamic log file path
$LogDir = "C:\Temp"
if (!(Test-Path -Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }

$ComputerName = $env:COMPUTERNAME
$TimeStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$LogFile = Join-Path -Path $LogDir -ChildPath "$($ComputerName)_EdgeGameAssist_Remediation_$TimeStamp.log"

function Write-Log {
    param ([string]$Message, [string]$Type = "INFO")
    $LogTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$LogTime] [$Type] $Message"
    Write-Output $LogEntry
    Add-Content -Path $LogFile -Value $LogEntry
}

Write-Log "Starting full remediation for Microsoft.Edge.GameAssist..."

$PackageName = "Microsoft.Edge.GameAssist"

# 1. Terminate active Edge Game Assist background processes
Get-Process -Name "*GameAssist*", "*EdgeGame*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Write-Log "Terminated any active Edge Game Assist processes."

# 2. Run AppX removal for ALL ACTIVE user profiles
$UserPackages = Get-AppxPackage -AllUsers -Name $PackageName -ErrorAction SilentlyContinue
if ($UserPackages) {
    foreach ($Pkg in $UserPackages) {
        Write-Log "Removing AppX package for active user context: $($Pkg.PackageFullName)" "ACTION"
        Remove-AppxPackage -Package $Pkg.PackageFullName -AllUsers -ErrorAction SilentlyContinue
    }
} else {
    Write-Log "No active AppX packages found for $PackageName."
}

# 3. Remove Provisioned package (prevents auto-install on new user logins)
$ProvisionedPackage = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq $PackageName }
if ($ProvisionedPackage) {
    Write-Log "Removing provisioned package from image: $($ProvisionedPackage.DisplayName)" "ACTION"
    Remove-AppxProvisionedPackage -Online -PackageName $ProvisionedPackage.PackageName -ErrorAction SilentlyContinue
} else {
    Write-Log "No provisioned package found for $PackageName."
}

# 4. Scrub OFFLINE user registry hives (captures inactive/logged-off profiles)
$UserProfiles = Get-CimInstance Win32_UserProfile | Where-Object { !$_.Special -and !$_.Loaded }

if ($UserProfiles) {
    Write-Log "Found $($UserProfiles.Count) inactive user profile(s) to inspect for residual keys."

    foreach ($Profile in $UserProfiles) {
        $HivePath = "$($Profile.LocalPath)\NTUSER.DAT"
        $UserSid = $Profile.SID
        
        if (Test-Path $HivePath) {
            $MountedKey = "HKU\Temp_$UserSid"
            Write-Log "Loading hive for SID $UserSid at path: $HivePath"
            
            $LoadResult = reg load $MountedKey $HivePath 2>&1
            if ($LASTEXITCODE -eq 0) {
                $AppXReg = "Registry::$MountedKey\Software\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Applications"
                $TargetKeys = Get-ChildItem -Path $AppXReg -ErrorAction SilentlyContinue | 
                    Where-Object { $_.PSChildName -like "*$PackageName*" }

                if ($TargetKeys) {
                    foreach ($Key in $TargetKeys) {
                        Write-Log "Removing offline AppX registry key: $($Key.PSChildName)" "ACTION"
                        Remove-Item -Path $Key.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                    }
                } else {
                    Write-Log "No matching residual keys found in offline hive for SID $UserSid."
                }

                [gc]::Collect()
                reg unload $MountedKey 2>&1 | Out-Null
                Write-Log "Unloaded hive for SID $UserSid."
            } else {
                Write-Log "Failed to mount hive for SID $UserSid. Output: $LoadResult" "WARNING"
            }
        }
    }
}

Write-Log "Remediation finished. Full log written to $LogFile"