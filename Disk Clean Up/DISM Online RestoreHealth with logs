<#
.SYNOPSIS
    Interactive Windows System Repair Tool.
.DESCRIPTION
    Performs DISM RestoreHealth and SFC Scannow with real-time log monitoring.
.NOTES
    Log File: C:\temp\WinRepair_YYYYMMDD_HHMMSS.log
#>

# ---------------------------------------------------------------------------
# 1. VARIABLES (Centralized Configuration)
# ---------------------------------------------------------------------------
$LogDir       = "C:\temp"
$DateStamp    = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile      = Join-Path $LogDir "WinRepair_$($DateStamp).log"
$ConnectionIP = "8.8.8.8" # Google DNS to verify outbound routing

# ---------------------------------------------------------------------------
# 2. FUNCTIONS & PRE-FLIGHT
# ---------------------------------------------------------------------------

function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")][string]$Level = "INFO"
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $FormattedMessage = "[$Timestamp] [$Level] $Message"
    
    $Color = switch($Level) {
        "ERROR" { "Red" }
        "WARN"  { "Yellow" }
        default { "Cyan" }
    }

    Write-Host $FormattedMessage -ForegroundColor $Color
    $FormattedMessage | Out-File -FilePath $LogFile -Append
}

# Ensure Log Directory
if (!(Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }

# Admin Check
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "Elevation Required. Please run as Administrator." "ERROR"
    exit 1001
}

# Internet Check (Required for Online RestoreHealth)
Write-Log "Checking internet connectivity..."
if (-not (Test-Connection -ComputerName $ConnectionIP -Count 1 -Quiet)) {
    Write-Log "No internet detected. DISM RestoreHealth requires an online connection." "ERROR"
    exit 1002
}

# ---------------------------------------------------------------------------
# 3. MAIN EXECUTION
# ---------------------------------------------------------------------------
try {
    Write-Log "--- Starting Repair Sequence ---"

    # Spawn Secondary Log Monitor
    $CBSLog = "C:\Windows\Logs\CBS\CBS.log"
    if (Test-Path $CBSLog) {
        Write-Log "Spawning live CBS log monitor..."
        $MonitorScript = "Get-Content -Path '$CBSLog' -Tail 10 -Wait"
        Start-Process powershell.exe -ArgumentList "-NoProfile", "-Command", $MonitorScript -Verb RunAs
    }

    # Step 1: DISM
    Write-Log "Phase 1: Running DISM RestoreHealth. This may take a while..."
    Repair-WindowsImage -Online -RestoreHealth -ErrorAction Stop
    Write-Log "Phase 1 Complete: Component Store repaired."

    # Step 2: SFC
    Write-Log "Phase 2: Running System File Checker (SFC)..."
    sfc /scannow
    Write-Log "Phase 2 Complete: System file integrity checked."

}
catch {
    Write-Log "An error occurred: $($_.Exception.Message)" "ERROR"
    exit 1003
}
finally {
    Write-Log "--- Sequence Finished ---"
    Write-Host "Detailed log saved to: $LogFile" -ForegroundColor Green
}

exit 0
