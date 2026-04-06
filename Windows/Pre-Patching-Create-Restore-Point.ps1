<#
.SYNOPSIS
    MSP Standard - Pre-Patching System Restore Point Creation
    
.DESCRIPTION
    Intended for ManageEngine Endpoint Central RMM.
    - Runs silently under SYSTEM context.
    - Automates log generation in C:\temp.
    - Bypasses the Windows 24-hour restore point frequency limit.
    - Checks for existing VSS/Restore processes to prevent collisions.
    - Returns specific exit codes for RMM reporting.

.NOTES
    Author: MSP Systems Engineer
    Version: 1.1
    Target: Windows 10, Windows 11
#>

# --------------------------------------------------------------------------
# VARIABLES & CONFIGURATION
# --------------------------------------------------------------------------
$RestorePrefix = "Pre-Patching"
$Timestamp     = Get-Date -Format "yyyy-MM-dd_HH-mm"
$LogDirectory  = "C:\temp"
$LogFileName   = "PrePatching_RestorePoint_$Timestamp.log"
$LogPath       = Join-Path $LogDirectory $LogFileName
$FullPointName = "$RestorePrefix $Timestamp"

# --------------------------------------------------------------------------
# EXIT CODES REFERENCE
# --------------------------------------------------------------------------
# 0   = Success
# 100 = Execution Safety: Process already running or VSS busy
# 101 = Environment Error: System Restore is disabled or unsupported
# 102 = Service Error: VSS service could not be started
# 103 = General Script Failure / Catch Block
# --------------------------------------------------------------------------

# --------------------------------------------------------------------------
# LOGGING FUNCTION (Silent)
# --------------------------------------------------------------------------
function Write-MSPLog {
    param([string]$Message)
    try {
        if (!(Test-Path $LogDirectory)) { 
            New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null 
        }
        $Entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
        $Entry | Out-File -FilePath $LogPath -Append -Encoding UTF8
    } catch {
        # Silently fail if logging is impossible
    }
}

# --------------------------------------------------------------------------
# SCRIPT EXECUTION
# --------------------------------------------------------------------------
try {
    Write-MSPLog "Starting automated restore point creation: $FullPointName"

    # 1. Execution Safety Check
    # Check if a restore point operation is already in progress or VSS is heavily loaded
    $vssProcess = Get-Process -Name "vssvc" -ErrorAction SilentlyContinue
    if ($vssProcess) {
        # If VSS is running and has been active for more than 1 minute of CPU time, it's likely busy
        if ($vssProcess.CPU -gt 60) {
            Write-MSPLog "CANCELLED: VSS Service (vssvc) appears busy. Exit code 100."
            exit 100
        }
    }

    # 2. Bypass Windows Restore Point Frequency (The 24-hour rule)
    $RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"
    if (!(Test-Path $RegPath)) { New-Item -Path $RegPath -Force | Out-Null }
    Set-ItemProperty -Path $RegPath -Name "SystemRestorePointCreationFrequency" -Value 0 -Type DWord -Force | Out-Null
    Write-MSPLog "Registry: Frequency limit bypassed (Value: 0)."

    # 3. Ensure System Restore is Enabled for C:
    # Some Windows builds disable this by default.
    Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
    Write-MSPLog "Environment: Attempted to enable Restore on C:\"

    # 4. Service Health Check
    $vssService = Get-Service -Name "vss" -ErrorAction SilentlyContinue
    if ($vssService.Status -eq 'Stopped') {
        Start-Service -Name "vss" -ErrorAction SilentlyContinue
    }

    # 5. Create Restore Point
    Write-MSPLog "Action: Creating restore point..."
    
    # Checkpoint-Computer is the standard cmdlet for this task
    Checkpoint-Computer -Description $FullPointName -RestorePointType "APPLICATION_INSTALL" -ErrorAction Stop
    
    Write-MSPLog "SUCCESS: Restore point '$FullPointName' created."
    exit 0

}
catch {
    $Err = $_.Exception.Message
    Write-MSPLog "CRITICAL FAILURE: $Err"
    
    # Identify specific failure types for RMM exit codes
    if ($Err -like "*disabled*") { exit 101 }
    if ($Err -like "*vss*") { exit 102 }
    
    exit 103
}