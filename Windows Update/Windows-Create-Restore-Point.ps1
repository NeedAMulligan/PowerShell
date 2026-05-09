<#
.SYNOPSIS
    Creates a System Restore Point with a dynamic timestamp name.
    
.EXITCODES
    0    = Success
    1001 = Script not running with Administrative privileges
    1002 = Failed to enable System Restore on C:
    1003 = Failed to create Restore Point
#>

$ExitCode = 0
$ErrorActionPreference = "Stop"

# Define Exit Codes
# 0: Success
# 1001: Prerequisite: Admin Rights Missing
# 1002: Failed to enable Protection
# 1003: Checkpoint Creation Failed

# Logging Setup
$LogPath = "C:\temp"
if (-not (Test-Path $LogPath)) { New-Item -Path $LogPath -ItemType Directory -Force }
$TimeStamp = Get-Date -Format "yyyyMMdd_HHmm"
$LogFile = Join-Path $LogPath "CreateRestorePoint_$($TimeStamp).log"

function Write-Log {
    param([string]$Message)
    $LogEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
    Add-Content -Path $LogFile -Value $LogEntry
}

Write-Log "Starting Restore Point Creation Script."

# Check for Admin Rights
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "ERROR: Script must be run as Administrator."
    exit 1001
}

try {
    # Bypass the 24-hour frequency restriction (SystemRestorePointCreationFrequency)
    Write-Log "Adjusting registry to allow multiple restore points per day."
    $RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"
    Set-ItemProperty -Path $RegPath -Name "SystemRestorePointCreationFrequency" -Value 0 -Force

    # Ensure System Protection is enabled for C:
    Write-Log "Ensuring System Protection is enabled on C:\"
    Enable-ComputerRestore -Drive "C:\"
    
    # Create the Restore Point
    $RestoreName = "Manual-Restore-Point-$(Get-Date -Format 'yyyy-MM-dd_HHmm')"
    Write-Log "Attempting to create restore point: $RestoreName"
    
    Checkpoint-Computer -Description $RestoreName -RestorePointType "APPLICATION_INSTALL"
    
    Write-Log "SUCCESS: Restore point '$RestoreName' created successfully."
}
catch {
    Write-Log "ERROR: Failed to create restore point. Exception: $($_.Exception.Message)"
    $ExitCode = 1003
}

exit $ExitCode