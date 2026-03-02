<#
.SYNOPSIS
    Enables Windows Recovery Environment (WinRE) for Quick Machine Recovery on Windows 11 Pro.

.DESCRIPTION
    Standardized MSP script to ensure WinRE is active. It performs pre-flight checks 
    for administrative privileges, process safety, disk space, and BitLocker status.
    
    Target: Windows 11 Pro
    Automation: Completely silent, no user interaction.
    Logging: Dynamic logs sent to C:\Temp\

.VARIABLES
    Modify these at the top for specific MSP environment overrides.
#>

# ======================================================================================
# VARIABLES & CONFIGURATION
# ======================================================================================
$LogDir         = "C:\Temp"
$Timestamp      = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFileName    = "QuickMachineRecovery-Enabled-$Timestamp.log"
$LogPath        = Join-Path $LogDir $LogFileName
$TargetProcess  = "reagentc"
$MinFreeSpaceGB = 1  # Safety buffer for WinRE staging/updates

# ======================================================================================
# EXIT CODES
# ======================================================================================
# 0   = SUCCESS: WinRE is Enabled (or was already enabled)
# 1   = FAILURE: General error or reagentc failed operation
# 100 = ABORTED: reagentc.exe is already running
# 101 = ABORTED: Script not running with Administrative/SYSTEM privileges
# 102 = ABORTED: Insufficient disk space (< 1GB)
# ======================================================================================

# ======================================================================================
# HELPER FUNCTIONS
# ======================================================================================
function Write-Log {
    param([string]$Message)
    $Date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$Date] $Message" | Out-File -FilePath $LogPath -Append
}

# ======================================================================================
# EXECUTION LOGIC
# ======================================================================================

try {
    # 1. Ensure Log Directory Exists
    if (!(Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }

    Write-Log "--- STARTING QUICK MACHINE RECOVERY ENABLEMENT ---"

    # 2. Privilege Check
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Log "CRITICAL: Script must run as SYSTEM/Administrator. Exiting (Code 101)."
        exit 101
    }

    # 3. Execution Safety Check (Process Guard)
    if (Get-Process $TargetProcess -ErrorAction SilentlyContinue) {
        Write-Log "ABORT: $TargetProcess is already running. Preventing conflict. Exiting (Code 100)."
        exit 100
    }

    # 4. Check Disk Space on C:
    $Drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $FreeSpaceGB = [math]::Round($Drive.FreeSpace / 1GB, 2)
    if ($FreeSpaceGB -lt $MinFreeSpaceGB) {
        Write-Log "ABORT: Low disk space ($FreeSpaceGB GB). 1GB required for safe WinRE operations. Exiting (Code 102)."
        exit 102
    }
    Write-Log "System Drive Check: $FreeSpaceGB GB available."

    # 5. BitLocker Status Audit
    try {
        $BLStatus = Get-BitLockerVolume -MountPoint "C:" -ErrorAction SilentlyContinue
        if ($null -ne $BLStatus) {
            Write-Log "BitLocker Status: Protection is $($BLStatus.ProtectionStatus)"
        } else {
            Write-Log "BitLocker Status: No BitLocker detected on C:."
        }
    } catch {
        Write-Log "Warning: BitLocker check encountered an error, but proceeding with WinRE enablement."
    }

    # 6. WinRE Enablement Logic
    $REInfo = reagentc /info
    Write-Log "Current WinRE Status: $(($REInfo -match 'Windows RE status:.*').Trim())"

    if ($REInfo -match "Enabled") {
        Write-Log "WinRE is already enabled. No further action needed."
        exit 0
    } else {
        Write-Log "Attempting to enable WinRE..."
        $REEnable = reagentc /enable
        
        if ($REEnable -match "Operation Successful") {
            Write-Log "SUCCESS: WinRE has been enabled successfully."
            exit 0
        } else {
            Write-Log "ERROR: reagentc reported a failure: $REEnable"
            exit 1
        }
    }

}
catch {
    Write-Log "CRITICAL EXCEPTION: $($_.Exception.Message)"
    exit 1
}
finally {
    Write-Log "--- END OF SCRIPT EXECUTION ---"
}