<#
.SYNOPSIS
    Activates BitLocker protection on encrypted but unowned volumes.
.DESCRIPTION
    1. Performs Pre-flight checks (Admin rights, TPM, Disk Space, AC Power).
    2. Initializes TPM if not ready.
    3. Adds a Local Recovery Password.
    4. Enables Protection.
    5. Outputs recovery information to Console only.
.PARAMETER Interactive
    Prompts the user before taking action on a drive.
.EXAMPLE
    .\Activate-BitLockerLocal.ps1
#>

# ---------------------------------------------------------------------------
# VARIABLES
# ---------------------------------------------------------------------------
$Global:Variables = @{
    LogPath             = "C:\temp"
    MinDiskSpaceGB      = 2
    RequireACPower      = $true
    BackupToAD          = $false # Set to $true if domain joined
    ScriptLogName       = "BitLockerActivator_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
}

# EXIT CODES:
# 0: Success
# 1: Not running as Administrator
# 2: TPM Initialization Failed
# 3: Pre-flight Check Failed (Power/Space)
# 4: User Aborted Execution
# 5: Bitlocker Activation Failed

# ---------------------------------------------------------------------------
# FUNCTIONS
# ---------------------------------------------------------------------------

function Write-Log {
    param([string]$Message, [ValidateSet("INFO", "WARN", "ERROR")] $Level = "INFO")
    $Stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Line = "[$Stamp] [$Level] $Message"
    
    # Per user request: Log operational flow to file, but NOT recovery info.
    if (-not (Test-Path $Global:Variables.LogPath)) { New-Item -Path $Global:Variables.LogPath -ItemType Directory | Out-Null }
    $Line | Out-File -FilePath (Join-Path $Global:Variables.LogPath $Global:Variables.ScriptLogName) -Append
    
    switch ($Level) {
        "INFO"  { Write-Host $Line -ForegroundColor Cyan }
        "WARN"  { Write-Host $Line -ForegroundColor Yellow }
        "ERROR" { Write-Host $Line -ForegroundColor Red }
    }
}

function Test-PreFlight {
    Write-Log "Running Pre-flight checks..."

    # 1. Admin Check
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Log "Script must be run as Administrator." "ERROR"
        exit 1
    }

    # 2. Power Check
    if ($Global:Variables.RequireACPower) {
        $Battery = Get-CimInstance -ClassName Win32_Battery
        if ($Battery -and $Battery.BatteryStatus -ne 2) {
            Write-Log "Device is on Battery. Please connect AC power before proceeding." "ERROR"
            exit 3
        }
    }

    # 3. Space Check
    $SystemDrive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $FreeSpaceGB = [math]::Round($SystemDrive.FreeSpace / 1GB, 2)
    if ($FreeSpaceGB -lt $Global:Variables.MinDiskSpaceGB) {
        Write-Log "Insufficient disk space ($FreeSpaceGB GB). Required: $($Global:Variables.MinDiskSpaceGB) GB." "ERROR"
        exit 3
    }

    Write-Log "Pre-flight checks passed."
}

function Initialize-LocalTPM {
    Write-Log "Checking TPM Status..."
    $TPM = Get-Tpm
    if (-not $TPM.TpmReady) {
        if ($TPM.TpmPresent) {
            Write-Log "TPM present but not ready. Attempting initialization..." "WARN"
            try {
                Initialize-Tpm -ErrorAction Stop
                Start-Sleep -Seconds 5
            } catch {
                Write-Log "Failed to initialize TPM: $($_.Exception.Message)" "ERROR"
                exit 2
            }
        } else {
            Write-Log "No TPM detected on this system." "ERROR"
            exit 2
        }
    } else {
        Write-Log "TPM is ready."
    }
}

# ---------------------------------------------------------------------------
# MAIN EXECUTION BLOCK
# ---------------------------------------------------------------------------

Test-PreFlight
Initialize-LocalTPM

$Volumes = Get-BitLockerVolume | Where-Object { $_.ProtectionStatus -eq 'Off' -and $_.VolumeStatus -eq 'FullyEncrypted' }

if ($null -eq $Volumes) {
    Write-Log "No volumes found matching 'Encrypted but Not Enabled' criteria."
    exit 0
}

foreach ($Vol in $Volumes) {
    $Drive = $Vol.MountPoint
    Write-Log "Target Volume Found: $Drive"

    # INTERACTIVE PROMPT
    $Confirm = Read-Host "Would you like to enable BitLocker protection for $Drive? (Y/N)"
    if ($Confirm -ne 'Y') {
        Write-Log "Skipping $Drive per user request." "WARN"
        continue
    }

    try {
        Write-Log "Adding Recovery Password protector to $Drive..."
        $RP = Add-BitLockerKeyProtector -MountPoint $Drive -RecoveryPasswordProtector -ErrorAction Stop
        
        # SENSITIVE DATA: Console Only
        Write-Host "`n[!!!] RECOVERY KEY FOR $Drive [!!!]" -ForegroundColor Black -BackgroundColor Yellow
        Write-Host "Password: $($RP.KeyProtector.RecoveryPassword)" -ForegroundColor Green
        Write-Host "Please save this manually in a secure location. It will NOT be logged.`n"

        Write-Log "Adding TPM Protector..."
        Add-BitLockerKeyProtector -MountPoint $Drive -TpmProtector -ErrorAction Stop

        Write-Log "Enabling Protection..."
        Resume-BitLocker -MountPoint $Drive -ErrorAction Stop
        
        Write-Log "BitLocker successfully activated on $Drive."
    } catch {
        Write-Log "Failed to activate BitLocker on $Drive: $($_.Exception.Message)" "ERROR"
        exit 5
    }
}

Write-Log "Script execution complete."
exit 0
