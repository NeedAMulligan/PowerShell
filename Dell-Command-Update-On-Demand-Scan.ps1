<#
.SYNOPSIS
    Dell Command | Update - On-Demand Driver & Firmware Patching (Excluding BIOS)
.DESCRIPTION
    1. Verifies DCU CLI presence.
    2. Checks for updates, specifically filtering out BIOS updates.
    3. Installs all applicable drivers, applications, and non-BIOS firmware.
    4. Automatically suspends BitLocker during the process to prevent boot issues.
.NOTES
    Optimized for ManageEngine / SYSTEM context. No reboot is forced by the script.
#>

# ==============================================================================
# 1. VARIABLES & CONFIGURATION
# ==============================================================================
$LogDir         = "C:\temp"
$Timestamp      = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile        = Join-Path $LogDir "DCU_OnDemand_Patching_$($Timestamp).log"
$DcuCliPath     = "${env:ProgramFiles}\Dell\CommandUpdate\dcu-cli.exe"
$GlobalExitCode = 0

# ==============================================================================
# 2. LOGGING FUNCTION
# ==============================================================================
function Write-Log {
    param([string]$Message, [ValidateSet("INFO", "WARN", "ERROR")] $Level = "INFO")
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    $Entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Add-Content -Path $LogFile -Value $Entry
    # Write to console for RMM logging
    Write-Output $Entry
}

# ==============================================================================
# 3. PRE-FLIGHT CHECKS
# ==============================================================================
$Manufacturer = (Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer
if ($Manufacturer -notlike "*Dell*") {
    Write-Log "Non-Dell Hardware detected ($Manufacturer). Aborting." "ERROR"
    exit 1001 
}

if (-not (Test-Path $DcuCliPath)) {
    Write-Log "DCU CLI not found at $DcuCliPath. Please ensure DCU 5.6 is installed." "ERROR"
    exit 1003
}

# ==============================================================================
# 4. PATCHING EXECUTION
# ==============================================================================
Write-Log "Starting On-Demand Patching (Excluding BIOS updates)..."

# Parameters used:
# /applyUpdates - Installs the found updates
# -updateType=sys,driver - Includes system and drivers (explicitly omitting 'bios')
# -reboot=disable - Prevents the CLI from forcing an immediate restart
# -bitlockerSuspend=enable - Suspends BitLocker protectors for the session
$PatchArgs = @(
    "/applyUpdates",
    "-updateType=sys,driver",
    "-reboot=disable",
    "-bitlockerSuspend=enable"
)

try {
    Write-Log "Running: dcu-cli.exe $($PatchArgs -join ' ')"
    $Process = Start-Process -FilePath $DcuCliPath -ArgumentList $PatchArgs -Wait -PassThru -NoNewWindow

    # Handle Exit Codes
    # 0 = Success (No updates needed or all installed)
    # 1 = General Error
    # 2 = Reboot Required
    # 3 = Another instance running
    
    switch ($Process.ExitCode) {
        0 { 
            Write-Log "Patching completed successfully. No further action needed."
            $GlobalExitCode = 0 
        }
        2 { 
            Write-Log "Updates installed successfully, but a REBOOT is required." "WARN"
            $GlobalExitCode = 3010 
        }
        3 {
            Write-Log "DCU is already running another task. Try again later." "ERROR"
            exit 1618
        }
        default {
            Write-Log "DCU CLI returned exit code: $($Process.ExitCode)" "ERROR"
            $GlobalExitCode = 1005
        }
    }
} catch {
    Write-Log "A critical error occurred: $($_.Exception.Message)" "ERROR"
    exit 1005
}

Write-Log "On-Demand Patching Script Finished."
exit $GlobalExitCode