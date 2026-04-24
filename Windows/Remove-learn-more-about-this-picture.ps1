<#
.SYNOPSIS
    MSP-Standard script to remove "Learn more about this picture" icon for all users.
    
.DESCRIPTION
    1. Validates OS version (Windows 11).
    2. Modifies Registry for current logged-in users.
    3. Loads and modifies Registry for offline/inactive users.
    4. Modifies the Default User hive for future profile creation.
    5. Restarts Explorer for the logged-in user to apply changes.

.NOTES
    Author: Gemini (MSP Script Creator)
    Requirement: Must run as SYSTEM.
#>

# --------------------------------------------------------------------------
# 1. Variables & Global Settings
# --------------------------------------------------------------------------
$LogPath      = "C:\temp"
$TargetGUID   = "{2cc5ca98-6485-489a-920e-b3e88a6ccce3}"
$TargetOS     = "11"
$Timestamp    = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFileName  = "Remove_SpotlightIcon_$Timestamp.log"
$FullLogPath  = Join-Path $LogPath $LogFileName

# Ensure log directory exists
if (!(Test-Path $LogPath)) { New-Item -Path $LogPath -ItemType Directory -Force | Out-Null }

# --------------------------------------------------------------------------
# 2. Logging & Helper Functions
# --------------------------------------------------------------------------
function Write-MSPLog {
    param([string]$Message)
    $Entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
    $Entry | Out-File -FilePath $FullLogPath -Append
    # Also write to host for RMM console capture
    Write-Output $Entry
}

function Invoke-RegistryFix {
    param([string]$HivePath)
    try {
        # Action 1: Remove from Desktop NameSpace
        $NameSpacePath = "$HivePath\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\$TargetGUID"
        if (Test-Path $NameSpacePath) {
            Remove-Item -LiteralPath $NameSpacePath -Force -ErrorAction Stop
            Write-MSPLog "Successfully removed NameSpace key from $HivePath"
        }

        # Action 2: Set HideDesktopIcons value
        $HidePath = "$HivePath\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"
        if (!(Test-Path $HidePath)) {
            New-Item -Path $HidePath -Force -ErrorAction SilentlyContinue | Out-Null
        }
        
        New-ItemProperty -LiteralPath $HidePath -Name $TargetGUID -Value 1 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        Write-MSPLog "Set HideDesktopIcons value to 1 in $HivePath"
    }
    catch {
        Write-MSPLog "WARNING: Could not process $HivePath. Details: $($_.Exception.Message)"
    }
}

# --------------------------------------------------------------------------
# 3. Execution Safety & OS Check
# --------------------------------------------------------------------------
Write-MSPLog "Initiating Script: Spotlight Icon Removal."

$OSVersion = (Get-WmiObject -Class Win32_OperatingSystem).Caption
if ($OSVersion -notlike "*Windows 11*") {
    Write-MSPLog "ABORT: OS is $OSVersion. This script only targets Windows 11. Exit Code 2."
    exit 2
}

# --------------------------------------------------------------------------
# 4. Main Logic: Registry Manipulation
# --------------------------------------------------------------------------
try {
    # Part A: Current Loaded Hives (including logged-in users)
    $LoadedHives = Get-ChildItem Registry::HKEY_USERS | Where-Object { $_.Name -match "S-1-5-21-[\d\-]+$" }
    foreach ($Hive in $LoadedHives) {
        Write-MSPLog "Processing active user hive: $($Hive.Name)"
        Invoke-RegistryFix -HivePath "Registry::HKEY_USERS\$($Hive.PSChildName)"
    }

    # Part B: Offline Users (Iterating through C:\Users)
    $ProfileList = Get-ChildItem "C:\Users" -Directory | Where-Object { $_.Name -notmatch "Public|All Users|Default" }
    foreach ($UserDir in $ProfileList) {
        $NTUserPath = Join-Path $UserDir.FullName "ntuser.dat"
        $Username = $UserDir.Name
        
        if (Test-Path $NTUserPath) {
            Write-MSPLog "Loading offline hive for: $Username"
            $TempHiveName = "TempHive_$Username"
            
            # Using reg.exe to load hive
            & reg load "HKU\$TempHiveName" "$NTUserPath" 2>&1 | Out-Null
            
            Invoke-RegistryFix -HivePath "Registry::HKEY_USERS\$TempHiveName"
            
            # Unload hive with garbage collection to ensure file unlock
            [gc]::Collect()
            [gc]::WaitForPendingFinalizers()
            & reg unload "HKU\$TempHiveName" 2>&1 | Out-Null
            Write-MSPLog "Unloaded hive for: $Username"
        }
    }

    # Part C: Future Users (The Default Hive)
    Write-MSPLog "Applying fix to Default User hive for future profiles."
    & reg load "HKU\DefaultUser" "C:\Users\Default\NTUSER.DAT" 2>&1 | Out-Null
    Invoke-RegistryFix -HivePath "Registry::HKEY_USERS\DefaultUser"
    & reg unload "HKU\DefaultUser" 2>&1 | Out-Null

    # --------------------------------------------------------------------------
    # 5. Explorer Refresh Logic
    # --------------------------------------------------------------------------
    Write-MSPLog "Restarting Explorer to apply changes."
    Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
    # Note: Explorer will automatically restart when stopped under most Windows configurations.
    
    Write-MSPLog "Script completed successfully. Exit Code 0."
    exit 0

}
catch {
    Write-MSPLog "CRITICAL FAILURE: $($_.Exception.Message)"
    exit 1
}
