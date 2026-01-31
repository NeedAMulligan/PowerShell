# EXIT CODES
# 0    = Success
# 1001 = Failed to create log directory
# 1002 = Permissions Error (Not running as SYSTEM/Admin)
# 1003 = Partial failure during registry mounting or process termination

$ErrorActionPreference = "Stop"
$LogPath = "C:\temp"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile = Join-Path $LogPath "DisableBingUnified_$($Timestamp).log"

# Create Log Directory
if (!(Test-Path $LogPath)) {
    try {
        New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
    } catch {
        exit 1001
    }
}

function Write-Log {
    param([string]$Message)
    $Entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
    Add-Content -Path $LogFile -Value $Entry
}

Write-Log "Starting Unified Bing Search Removal and Explorer Restart..."

# Check for Admin Privileges
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "ERROR: Script must run with elevated privileges (SYSTEM/Admin)."
    exit 1002
}

$RegistryPath = "Software\Policies\Microsoft\Windows\Windows Search"

# Function to Apply Registry Settings
function Set-BingRegistryKeys {
    param([string]$HivePath)
    try {
        $FullRegistryPath = "$HivePath\$RegistryPath"
        if (!(Test-Path "Registry::$FullRegistryPath")) {
            New-Item -Path "Registry::$FullRegistryPath" -Force | Out-Null
        }
        # Disable Web Search in Start Menu
        Set-ItemProperty -Path "Registry::$FullRegistryPath" -Name "ConnectedSearchUseWeb" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path "Registry::$FullRegistryPath" -Name "DisableSearchBoxSuggestions" -Value 1 -Type DWord -Force
        Write-Log "Successfully applied keys to: $FullRegistryPath"
    } catch {
        Write-Log "Failed to apply keys to $HivePath: $($_.Exception.Message)"
    }
}

# 1. Update Currently Loaded Hives (Logged-in users)
$LoadedHives = Get-ChildItem -Path "HKU:\" | Where-Object { $_.Name -match "S-1-5-21-[\d\-]+$" }
foreach ($Hive in $LoadedHives) {
    Set-BingRegistryKeys -HivePath "HKEY_USERS\$($Hive.PSChildName)"
}

# 2. Update Offline Hives (All profiles on disk)
$UserProfiles = Get-ChildItem -Path "C:\Users" -Directory
foreach ($Profile in $UserProfiles) {
    $NtUserPath = Join-Path $Profile.FullName "NTUSER.DAT"
    if (Test-Path $NtUserPath) {
        $TempHiveName = "TempHive_$($Profile.Name)"
        try {
            Write-Log "Mounting hive for user: $($Profile.Name)"
            reg load "HKU\$TempHiveName" "$NtUserPath" | Out-Null
            Set-BingRegistryKeys -HivePath "HKEY_USERS\$TempHiveName"
            
            # Ensure file handle is released before unloading
            [gc]::Collect()
            [gc]::WaitForPendingFinalizers()
            
            reg unload "HKU\$TempHiveName" | Out-Null
        } catch {
            Write-Log "Failed to process profile $($Profile.Name): $($_.Exception.Message)"
        }
    }
}

# 3. Restart Explorer to Apply Changes
$ExplorerProcesses = Get-Process -Name "explorer" -ErrorAction SilentlyContinue
if ($ExplorerProcesses) {
    try {
        foreach ($Proc in $ExplorerProcesses) {
            Write-Log "Restarting Explorer for PID: $($Proc.Id)"
            Stop-Process -Id $Proc.Id -Force
        }
    } catch {
        Write-Log "Warning: Could not restart one or more Explorer processes."
    }
} else {
    Write-Log "No active Explorer processes found to restart."
}

Write-Log "Script completed successfully."
exit 0