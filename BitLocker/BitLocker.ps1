<#
.SYNOPSIS
    Interactive BitLocker Deployment Tool with Progress Monitoring.
.DESCRIPTION
    Initializes TPM-based encryption on C: (Used Space Only) and provides 
    a real-time progress bar until 100% completion is reached.
.NOTES
    Logging: C:\temp\BitLocker_Progress_YYYYMMDD.log
#>

# ---------------------------------------------------------------------------
# 1. VARIABLES
# ---------------------------------------------------------------------------
$TargetDrive      = "C:"
$LogPath          = "C:\temp"
$Timestamp        = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile          = Join-Path $LogPath "BitLocker_Progress_$Timestamp.log"
$EncryptionMethod = "XtsAes256"

# ---------------------------------------------------------------------------
# 2. FUNCTIONS
# ---------------------------------------------------------------------------
function Write-Log {
    param([string]$Message, [ValidateSet("INFO", "WARN", "ERROR")] $Level = "INFO")
    if (!(Test-Path $LogPath)) { New-Item -ItemType Directory -Path $LogPath -Force | Out-Null }
    Add-Content -Path $LogFile -Value "[$Timestamp][$Level] $Message"
}

function Get-BitLockerReport {
    $Tpm = Get-Tpm
    $Vol = Get-BitLockerVolume -MountPoint $TargetDrive
    return [PSCustomObject]@{
        TPM_Ready         = $Tpm.TpmReady
        ProtectionStatus  = $Vol.ProtectionStatus
        VolumeStatus      = $Vol.VolumeStatus
        EncryptionPercent = $Vol.EncryptionPercentage
    }
}

# ---------------------------------------------------------------------------
# 3. EXECUTION & PROGRESS MONITORING
# ---------------------------------------------------------------------------
Clear-Host
# Pre-flight check
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "CRITICAL: Administrator privileges required." -ForegroundColor Red
    exit 2
}

$Report = Get-BitLockerReport
Write-Log "Starting process for $TargetDrive." "INFO"

# Start Encryption if needed
if ($Report.VolumeStatus -eq "FullyDecrypted") {
    Write-Host "Adding TPM Protector and starting encryption..." -ForegroundColor Cyan
    Add-BitLockerKeyProtector -MountPoint $TargetDrive -TpmProtector | Out-Null
    Enable-BitLocker -MountPoint $TargetDrive -EncryptionMethod $EncryptionMethod -UsedSpaceOnly | Out-Null
    Write-Log "Encryption initiated (Used Space Only)." "INFO"
}

# Progress Monitoring Loop
Write-Host "Monitoring encryption progress. Do not close this window..." -ForegroundColor Yellow


while ($true) {
    $Status = Get-BitLockerVolume -MountPoint $TargetDrive
    $Percent = $Status.EncryptionPercentage
    
    # Display Progress Bar
    Write-Progress -Activity "BitLocker Encryption Progress" `
                   -Status "$Percent% Complete" `
                   -PercentComplete $Percent
    
    if ($Percent -eq 100 -and $Status.ProtectionStatus -eq "On") {
        Write-Progress -Activity "BitLocker Encryption Progress" -Completed
        break
    }
    
    if ($Status.VolumeStatus -eq "EncryptionPaused") {
        Write-Host "Encryption paused (Check AC Power). Resuming..." -ForegroundColor Red
        Resume-BitLocker -MountPoint $TargetDrive
    }

    Start-Sleep -Seconds 2
}

# Final Reusable Object Output
$FinalReport = Get-BitLockerReport
Write-Host "`n--- ENCRYPTION COMPLETE ---" -ForegroundColor Green
$FinalObject = [PSCustomObject]@{
    ComputerName      = $env:COMPUTERNAME
    Status            = $FinalReport.ProtectionStatus
    FinalPercentage   = $FinalReport.EncryptionPercent
    CompletionTime    = Get-Date
}
$FinalObject | Format-Table
Write-Log "Encryption reached 100% successfully." "INFO"

exit 0
