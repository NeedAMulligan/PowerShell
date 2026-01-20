# -------------------------------------------------------------------------
# EXIT CODES:
# 0    = Success (All artifacts removed)
# 1001 = System already clean (No services or files found)
# 1002 = Log Directory creation failed
# 1003 = Critical Failure during execution
# 1004 = Verification Failed (Residual artifacts detected)
# -------------------------------------------------------------------------

$TargetName = "BASupportExpres"
$ProcessName = "BASupportExpress"
$ProgramFilesPath = "${env:Program Files (x86)}\N-able Technologies\Take Control Agent"

# --- Setup Logging ---
$LogPath = "C:\temp"
$ScriptName = "Remove-NAble_TotalScrub"
$Timestamp = Get-Date -Format "yyyyMMdd-HHmm"
$LogFile = Join-Path $LogPath "$($ScriptName)_$($Timestamp).log"

if (-not (Test-Path $LogPath)) {
    try { 
        New-Item -ItemType Directory -Path $LogPath -Force -ErrorAction Stop | Out-Null 
    } catch { 
        exit 1002 
    }
}

# Renamed function to avoid recursion/naming collisions
function Write-ToLogFile {
    param ([string]$Message)
    $Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$Time] $Message" | Out-File -FilePath $LogFile -Append -Encoding UTF8
}

try {
    Write-ToLogFile "INITIATING FULL SYSTEM SCRUB: N-Able Take Control"

    # --- 1. Process Termination ---
    $ActiveProcesses = Get-Process -Name "$ProcessName*" -ErrorAction SilentlyContinue
    if ($ActiveProcesses) {
        Write-ToLogFile "Killing $($ActiveProcesses.Count) active processes..."
        Stop-Process -Name "$ProcessName*" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3 
    }

    # --- 2. Service Removal ---
    $Services = Get-Service | Where-Object { $_.Name -like "*$TargetName*" -or $_.DisplayName -like "*$TargetName*" }
    foreach ($Svc in $Services) {
        Write-ToLogFile "Removing Service: $($Svc.Name)"
        # Using sc.exe directly for more reliable removal in SYSTEM context
        & sc.exe stop $Svc.Name | Out-Null
        & sc.exe delete $Svc.Name | Out-Null
    }

    # --- 3. Registry Purge (Service, Software, and Uninstall keys) ---
    $RegPaths = @(
        "HKLM:\SYSTEM\CurrentControlSet\Services\$TargetName*",
        "HKLM:\SOFTWARE\WOW6432Node\BeAnywhere Support Express",
        "HKLM:\SOFTWARE\BeAnywhere Support Express",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{701416BA-6F6E-4543-A3B0-432850E53D8F}_is1",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\BeAnywhere Support Express*"
    )

    foreach ($RegPath in $RegPaths) {
        if (Test-Path $RegPath) {
            Write-ToLogFile "Purging Registry Key: $RegPath"
            Remove-Item -Path $RegPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # --- 4. System-Wide File Removal ---
    if (Test-Path $ProgramFilesPath) {
        Write-ToLogFile "Deleting Program Files directory: $ProgramFilesPath"
        Remove-Item -Path $ProgramFilesPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    # --- 5. Multi-User Profile AppData Sweep ---
    Write-ToLogFile "Scanning User Profiles for AppData artifacts..."
    $UserProfiles = Get-ChildItem -Path "C:\Users" -Directory
    foreach ($Profile in $UserProfiles) {
        $AppDataPaths = @(
            "$($Profile.FullName)\AppData\Local\BeAnywhere Support Express",
            "$($Profile.FullName)\AppData\LocalLow\BeAnywhere Support Express",
            "$($Profile.FullName)\AppData\Roaming\BeAnywhere Support Express"
        )

        foreach ($Path in $AppDataPaths) {
            if (Test-Path $Path) {
                Write-ToLogFile "  Removing AppData for $($Profile.Name): $Path"
                Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # --- 6. Final Verification ---
    $RemainingSvc = Get-Service | Where-Object { $_.Name -like "*$TargetName*" }
    $RemainingReg = $RegPaths | Where-Object { Test-Path $_ }
    
    if ($RemainingSvc -or $RemainingReg) {
        Write-ToLogFile "VERIFICATION FAILED: Residual system artifacts detected."
        exit 1004
    }

    Write-ToLogFile "DEEP CLEAN COMPLETE. System is clean."
    exit 0

} catch {
    Write-ToLogFile "CRITICAL ERROR: $($_.Exception.Message)"
    exit 1003
}