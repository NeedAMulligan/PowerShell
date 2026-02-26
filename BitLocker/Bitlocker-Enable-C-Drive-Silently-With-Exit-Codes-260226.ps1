<#
.SYNOPSIS
    Interactively enables BitLocker on the C: drive.
.DESCRIPTION
    Validates Admin rights and TPM status, then prompts the user to begin encryption. 
    Displays the Recovery Key to the console for manual capture and logs the Key ID.
.NOTES
    Log Path: C:\temp\BitLocker_Enable_YYYYMMDD_HHMMSS.log
#>

# ---------------------------------------------------------------------------
# 1. VARIABLES & CONFIGURATION
# ---------------------------------------------------------------------------
$Config = @{
    LogDirectory      = "C:\temp"
    LogFileName       = "BitLocker_Enable_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    EncryptionMethod  = "XtsAes256"
    TargetDrive       = "C:"
}

# ---------------------------------------------------------------------------
# 2. HELPER FUNCTIONS
# ---------------------------------------------------------------------------
function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message, 
        [ValidateSet("INFO", "WARN", "ERROR")][string]$Level = "INFO"
    )
    $Stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogLine = "[$Stamp] [$Level] $Message"
    
    # Ensure Log Directory exists
    if (!(Test-Path $Config.LogDirectory)) { 
        try { New-Item -Path $Config.LogDirectory -ItemType Directory -ErrorAction Stop | Out-Null }
        catch { Write-Host "CRITICAL: Could not create log directory at $($Config.LogDirectory)" -ForegroundColor Red }
    }
    
    # Log to file
    $LogLine | Out-File -FilePath (Join-Path $Config.LogDirectory $Config.LogFileName) -Append
    
    # Interactive Output
    switch ($Level) {
        "INFO"  { Write-Host $LogLine -ForegroundColor Cyan }
        "WARN"  { Write-Host $LogLine -ForegroundColor Yellow }
        "ERROR" { Write-Host $LogLine -ForegroundColor Red }
    }
}

function Test-IsAdmin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ---------------------------------------------------------------------------
# 3. PRE-FLIGHT CHECKS
# ---------------------------------------------------------------------------
Write-Log "Initializing Pre-flight checks..."

# Check Admin
if (-not (Test-IsAdmin)) {
    Write-Log "ERROR: Script must be run with elevated (Administrator) privileges." "ERROR"
    exit 2
}

# Check TPM Status
$TPM = Get-Tpm
if (-not $TPM.TpmPresent) {
    Write-Log "ERROR: TPM not detected. This script requires a TPM for local encryption." "ERROR"
    exit 3
}

if (-not $TPM.TpmReady) {
    Write-Log "WARN: TPM is present but not 'Ready'. Attempting to initialize..." "WARN"
    Initialize-Tpm | Out-Null
}

# Check Current Encryption State
$Volume = Get-BitLockerVolume -MountPoint $Config.TargetDrive -ErrorAction SilentlyContinue
if ($null -ne $Volume -and ($Volume.VolumeStatus -eq 'FullyEncrypted' -or $Volume.VolumeStatus -eq 'EncryptionInProgress')) {
    Write-Log "Drive $($Config.TargetDrive) is already encrypted or encrypting. No action needed." "WARN"
    exit 4
}

# ---------------------------------------------------------------------------
# 4. MAIN EXECUTION (INTERACTIVE)
# ---------------------------------------------------------------------------
try {
    Write-Host "`n--- BITLOCKER LOCAL SETUP ---" -ForegroundColor White -BackgroundColor DarkBlue
    $Confirmation = Read-Host "Proceed with enabling BitLocker on $($Config.TargetDrive)? (Y/N)"
    
    if ($Confirmation -ne "Y") {
        Write-Log "Operation cancelled by user." "INFO"
        exit 5
    }

    Write-Log "Adding Recovery Password protector..."
    $Protector = Add-BitLockerKeyProtector -MountPoint $Config.TargetDrive -RecoveryPasswordProtector
    $KeyID     = $Protector.KeyProtectorId
    $RawKey    = $Protector.RecoveryPassword

    # DISPLAY KEY TO USER (Not logged to file)
    Write-Host "`n****************************************************" -ForegroundColor Yellow
    Write-Host " BITLOCKER RECOVERY KEY GENERATED" -ForegroundColor Yellow
    Write-Host " Key ID: $KeyID"
    Write-Host " Recovery Key: $RawKey" -ForegroundColor Green
    Write-Host "****************************************************`n" -ForegroundColor Yellow
    Write-Host "Please record this key before proceeding.`n"
    
    Pause

    Write-Log "Key Protector created (ID: $KeyID). Starting encryption..." "INFO"
    
    # Enable BitLocker
    # Using -UsedSpaceOnly for speed on local interactive runs
    Enable-BitLocker -MountPoint $Config.TargetDrive `
                     -EncryptionMethod $Config.EncryptionMethod `
                     -UsedSpaceOnly `
                     -SkipHardwareTest
    
    Write-Log "SUCCESS: BitLocker encryption initiated for $($Config.TargetDrive)." "INFO"
    exit 0
}
catch {
    Write-Log "CRITICAL ERROR: $($_.Exception.Message)" "ERROR"
    exit 1
}
