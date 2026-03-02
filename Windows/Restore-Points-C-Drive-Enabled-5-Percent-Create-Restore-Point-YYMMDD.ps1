<#
.SYNOPSIS
    MSP Standard: Enables System Restore on C:, sets 5% quota, and forces a baseline with YYMMDD naming.

.DESCRIPTION
    1. Validates Administrative privileges and checks for installer conflicts.
    2. Verifies minimum disk space (10GB) before proceeding.
    3. Ensures VSS service is active.
    4. Bypasses the Windows 24-hour restore point frequency limitation.
    5. Enables System Restore on C: drive.
    6. Sets Shadow Storage maximum size to 5% via vssadmin.
    7. Creates an immediate restore point with a dynamic YYMMDD name.
    8. Logs all actions to C:\Temp with dynamic naming.

.VARIABLES
    $MaxStorageSize : Percentage of disk for restore points (Set to 5).
    $MinFreeSpaceGB : Minimum free space required to proceed (Set to 10).
    $DateStamp : The date formatted as YYMMDD.
    $RestorePointName : The final string used for the restore point description.

.EXIT CODES
    0    : Success
    1    : General Failure (Check Logs)
    2    : Insufficient Privileges
    3    : Insufficient Disk Space (< 10GB)
    1618 : Conflicting Process Running (Installer/Update in progress)
#>

# --------------------------------------------------------------------------
# VARIABLES & CONFIGURATION
# --------------------------------------------------------------------------
$MaxStorageSize   = 5 
$MinFreeSpaceGB   = 10
$DateStamp        = Get-Date -Format "yyMMdd"
$RestorePointName = "MSP_Baseline_$DateStamp"
$LogPath          = "C:\Temp"
$Timestamp        = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFileName      = "MSP_SystemRestore_Set_$($Timestamp).log"
$FullLogPath      = Join-Path -Path $LogPath -ChildPath $LogFileName
$TargetDrive      = "C:\"
$RegistryPath     = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"
$RegistryValue    = "SystemRestorePointCreationFrequency"

# --------------------------------------------------------------------------
# LOGGING FUNCTION
# --------------------------------------------------------------------------
function Write-Log {
    param([string]$Message)
    if (!(Test-Path $LogPath)) { New-Item -ItemType Directory -Path $LogPath -Force | Out-Null }
    $Entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
    $Entry | Out-File -FilePath $FullLogPath -Append -Encoding UTF8
}

# --------------------------------------------------------------------------
# PRE-EXECUTION CHECKS
# --------------------------------------------------------------------------
Write-Log "Initializing System Restore Script for C: Drive."

# 1. Admin Check
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "CRITICAL: Script must run as System/Administrator. Exiting."
    exit 2
}

# 2. Conflicting Process Check
$Conflicts = "msiexec", "TiWorker", "setup"
foreach ($Proc in $Conflicts) {
    if (Get-Process -Name $Proc -ErrorAction SilentlyContinue) {
        Write-Log "HALT: Conflicting process [$Proc] detected. Returning 1618 for RMM retry."
        exit 1618
    }
}

# 3. Disk Space Check
$DriveInfo = Get-PSDrive C
$FreeSpaceGB = [Math]::Round($DriveInfo.Free / 1GB, 2)
if ($FreeSpaceGB -lt $MinFreeSpaceGB) {
    Write-Log "HALT: Insufficient disk space ($FreeSpaceGB GB free). Required: $MinFreeSpaceGB GB."
    exit 3
}

# --------------------------------------------------------------------------
# MAIN EXECUTION
# --------------------------------------------------------------------------
try {
    # 4. Service Configuration
    Write-Log "Ensuring VSS (Volume Shadow Copy) is active."
    Get-Service -Name VSS | Set-Service -StartupType Manual -PassThru | Start-Service -ErrorAction SilentlyContinue

    # 5. Registry Bypass (Enable On-Demand Creation)
    Write-Log "Bypassing 24-hour restore point throttle via Registry."
    if (!(Test-Path $RegistryPath)) { New-Item -Path $RegistryPath -Force | Out-Null }
    Set-ItemProperty -Path $RegistryPath -Name $RegistryValue -Value 0 -Type DWord

    # 6. Enable Restore on C:
    Write-Log "Enabling Computer Restore on $TargetDrive"
    Enable-ComputerRestore -Drive $TargetDrive -ErrorAction Stop

    # 7. Set Storage Limit (5%)
    Write-Log "Adjusting Shadow Storage Max Size to $MaxStorageSize%."
    $vssResize = vssadmin resize shadowstorage /for=$TargetDrive /on=$TargetDrive /maxsize=$($MaxStorageSize)% 2>&1
    Write-Log "vssadmin Output: $vssResize"

    # 8. Create Dynamic Baseline Restore Point
    Write-Log "Attempting to create Restore Point: $RestorePointName"
    Checkpoint-Computer -Description $RestorePointName -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
    Write-Log "Restore point '$RestorePointName' created successfully."

    # 9. Reset Registry Frequency (Clean up)
    Write-Log "Restoring default restore point frequency throttle."
    Remove-ItemProperty -Path $RegistryPath -Name $RegistryValue -ErrorAction SilentlyContinue
    
    Write-Log "SUCCESS: System Restore active. Drive: $TargetDrive | Size: 5% | Name: $RestorePointName"
    exit 0
}
catch {
    Write-Log "ERROR: Execution failed. Details: $($_.Exception.Message)"
    if (Test-Path $RegistryPath) {
        Remove-ItemProperty -Path $RegistryPath -Name $RegistryValue -ErrorAction SilentlyContinue
    }
    exit 1
}