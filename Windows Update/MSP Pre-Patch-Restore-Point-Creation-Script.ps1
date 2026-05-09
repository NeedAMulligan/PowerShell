<#
.SYNOPSIS
    MSP Pre-Patch Gatekeeper: Verifies system health and creates a safety net before patching.

.DESCRIPTION
    1. Verifies Admin rights and detects installer conflicts.
    2. Checks for Pending Reboot/File Rename operations.
    3. Verifies Windows Recovery Environment (WinRE) is enabled.
    4. Ensures System Restore is active and set to 5% quota.
    5. Forces a "MSP_PrePatch_YYMMDD" restore point.
    6. Audits total points and logs everything silently to C:\Temp.

.VARIABLES
    $MaxStorageSize   : Target percentage (5%).
    $MinFreeSpaceGB   : Space check (Set to 10).
    $RestorePointName : Naming convention (MSP_PrePatch_YYMMDD).

.EXIT CODES
    0    : Success (Settings verified and Point created)
    1    : General Failure (Check logs)
    2    : Insufficient Privileges
    3    : Insufficient Disk Space (< 10GB)
    4    : WinRE is Disabled (Recovery accessibility risk)
    5    : Pending Reboot/Rename Detected (Patching stability risk)
    1618 : Conflicting Process Running (Installer/Update in progress)
#>

# --------------------------------------------------------------------------
# VARIABLES & CONFIGURATION
# --------------------------------------------------------------------------
$MaxStorageSize   = 5 
$MinFreeSpaceGB   = 10
$DateStamp        = Get-Date -Format "yyMMdd"
$RestorePointName = "MSP_PrePatch_$DateStamp"
$LogPath          = "C:\Temp"
$Timestamp        = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFileName      = "MSP_PrePatch_Gatekeeper_$($Timestamp).log"
$FullLogPath      = Join-Path -Path $LogPath -ChildPath $LogFileName
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
Write-Log "Initializing Pre-Patch Gatekeeper."

# 1. Admin Check
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "CRITICAL: Admin rights required."
    exit 2
}

# 2. Installer Conflict Check
$Conflicts = "msiexec", "TiWorker", "setup"
foreach ($Proc in $Conflicts) {
    if (Get-Process -Name $Proc -ErrorAction SilentlyContinue) {
        Write-Log "HALT: Installer [$Proc] active. Exiting (1618)."
        exit 1618
    }
}

# 3. Pending Reboot / File Rename Check
Write-Log "Checking for Pending File Rename Operations..."
$PendingRename = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue
if ($PendingRename) {
    Write-Log "HALT: Pending File Renames detected. System requires reboot before patching."
    exit 5
}

# 4. WinRE Health Check
Write-Log "Verifying Windows Recovery Environment (WinRE)..."
$WinRE = (reagentc /info | Out-String)
if ($WinRE -match "Disabled") {
    Write-Log "CRITICAL: WinRE is Disabled. Cannot proceed safely."
    exit 4
}

# 5. Disk Space Guardrail
$DriveInfo = Get-PSDrive C
if (([Math]::Round($DriveInfo.Free / 1GB, 2)) -lt $MinFreeSpaceGB) {
    Write-Log "HALT: Low Disk Space. Required: $MinFreeSpaceGB GB."
    exit 3
}

# --------------------------------------------------------------------------
# MAIN EXECUTION
# --------------------------------------------------------------------------
try {
    # 6. Service & Registry Setup
    Set-Service -Name VSS -StartupType Manual
    Start-Service -Name VSS -ErrorAction SilentlyContinue
    if (!(Test-Path $RegistryPath)) { New-Item -Path $RegistryPath -Force | Out-Null }
    Set-ItemProperty -Path $RegistryPath -Name $RegistryValue -Value 0 -Type DWord -Force

    # 7. Verify/Enable and Set Quota
    $IsProtected = (Get-WmiObject -Namespace root\default -Class SystemRestoreConfig).ReferenceId -ne 0 
    if ($null -eq $IsProtected -or $IsProtected -eq $false) {
        Write-Log "Enabling System Restore on C:..."
        Enable-ComputerRestore -Drive "C:\" -ErrorAction Stop
    }

    Write-Log "Setting Quota to $MaxStorageSize%..."
    try {
        vssadmin resize shadowstorage /for=C: /on=C: /maxsize=$($MaxStorageSize)% | Out-Null
    } catch {
        Write-Log "WARNING: Resize failed. Proceeding with existing quota."
    }

    # 8. Create Restore Point
    Write-Log "Creating Checkpoint: $RestorePointName"
    Checkpoint-Computer -Description $RestorePointName -RestorePointType "APPLICATION_INSTALL" -ErrorAction Stop
    
    # 9. SILENT AUDIT (Log Only)
    $Points = Get-ComputerRestorePoint -ErrorAction SilentlyContinue
    Write-Log "--- AUDIT SUMMARY ---"
    Write-Log "Total Points: $($Points.Count)"
    Write-Log "Latest Point: $($Points[-1].Description) created on $($Points[-1].CreationTime)"
    Write-Log "---------------------"

    # 10. Cleanup
    Remove-ItemProperty -Path $RegistryPath -Name $RegistryValue -ErrorAction SilentlyContinue
    Write-Log "SUCCESS: System prepared for patching."
    exit 0

} catch {
    Write-Log "FATAL ERROR: $($_.Exception.Message)"
    if (Test-Path $RegistryPath) {
        Remove-ItemProperty -Path $RegistryPath -Name $RegistryValue -ErrorAction SilentlyContinue
    }
    exit 1
}