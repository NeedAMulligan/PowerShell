<#
.SYNOPSIS
    Master BitLocker Management Utility for Local Systems.
.DESCRIPTION
    A modular menu-driven script to:
    1. Perform Compliance Audit (TPM/Secure Boot/Encryption Status)
    2. Sync/Generate Recovery Keys to Active Directory
    3. Cleanup redundant Recovery Protectors
.PARAMETER Interactive
    Defaults to true to allow for menu selection and pop-up alerts.
#>

[CmdletBinding()]
param([switch]$Interactive = $true)

# --------------------------------------------------------------------------
# VARIABLES & INITIALIZATION
# --------------------------------------------------------------------------
$ScriptName = "BitLocker-Master-Util"
$LogPath    = "C:\temp"
$Timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile    = Join-Path $LogPath "$($ScriptName)_$($Timestamp).log"

if (!(Test-Path $LogPath)) { New-Item -ItemType Directory -Path $LogPath -Force | Out-Null }

# --------------------------------------------------------------------------
# SHARED FUNCTIONS
# --------------------------------------------------------------------------

function Write-Log {
    param([string]$Message, [ValidateSet("INFO", "WARN", "ERROR", "AUDIT", "CLEANUP")] [string]$Level = "INFO")
    $LogEntry = "[$Timestamp] [$Level] - $Message"
    $Color = switch($Level) { "WARN" {"Yellow"} "ERROR" {"Red"} "AUDIT" {"Green"} "CLEANUP" {"Magenta"} Default {"Cyan"} }
    Write-Host $LogEntry -ForegroundColor $Color 
    $LogEntry | Out-File -FilePath $LogFile -Append
}

function Show-Msg {
    param([string]$Message, [int]$Icon = 64)
    $wshell = New-Object -ComObject WScript.Shell
    $wshell.Popup($Message, 0, "BitLocker Master Utility", $Icon) | Out-Null
}

function Get-AdminStatus {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Log "Critical: Administrator privileges required." "ERROR"
        exit 1
    }
}

# --------------------------------------------------------------------------
# FEATURE MODULES
# --------------------------------------------------------------------------

function Invoke-BitLockerAudit {
    Write-Log "Starting System Audit..." "AUDIT"
    $TPM = Get-Tpm
    $SB = Get-SecureBootUEFI -Name "SecureBoot" -ErrorAction SilentlyContinue
    $Vol = Get-BitLockerVolume -MountPoint "C:"
    
    Write-Log "--- AUDIT RESULTS ---" "AUDIT"
    Write-Log "TPM Present: $($TPM.TpmPresent)" "AUDIT"
    Write-Log "Secure Boot: $(if($null -eq $SB){"Unsupported"}else{$SB.Bytes[0] -eq 1})" "AUDIT"
    Write-Log "Encryption:  $($Vol.EncryptionMethod)" "AUDIT"
    Write-Log "Status:      $($Vol.ProtectionStatus)" "AUDIT"
    Write-Log "---------------------" "AUDIT"
    Show-Msg "Audit Complete. Check $LogFile for details."
}

function Invoke-KeySync {
    Write-Log "Starting AD Key Sync..."
    try {
        $Vol = Get-BitLockerVolume -MountPoint "C:"
        $Protector = $Vol.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }
        
        if ($null -eq $Protector) {
            Write-Log "No key found. Generating new protector..." "WARN"
            Add-BitLockerKeyProtector -MountPoint "C:" -RecoveryPasswordProtector | Out-Null
            $Vol = Get-BitLockerVolume -MountPoint "C:"
            $Protector = $Vol.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }
        }

        Backup-BitLockerKeyProtector -MountPoint "C:" -KeyProtectorId $Protector[0].KeyProtectorId -ErrorAction Stop
        Write-Log "Sync Successful: $($Protector[0].KeyProtectorId)" "INFO"
        Show-Msg "Recovery key successfully escrowed to AD."
    } catch {
        Write-Log "Sync Failed: $($_.Exception.Message)" "ERROR"
    }
}

function Invoke-ProtectorCleanup {
    Write-Log "Starting Protector Cleanup..." "CLEANUP"
    $Protectors = (Get-BitLockerVolume -MountPoint "C:").KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }
    
    if ($Protectors.Count -le 1) {
        Write-Log "No redundant protectors found." "INFO"
        return
    }

    $Latest = $Protectors[-1]
    $OldOnes = $Protectors[0..($Protectors.Count - 2)]

    try {
        Backup-BitLockerKeyProtector -MountPoint "C:" -KeyProtectorId $Latest.KeyProtectorId -ErrorAction Stop
        foreach ($P in $OldOnes) {
            Write-Log "Removing Old Protector: $($P.KeyProtectorId)" "CLEANUP"
            Remove-BitLockerKeyProtector -MountPoint "C:" -KeyProtectorId $P.KeyProtectorId
        }
        Show-Msg "Cleanup complete. Latest key preserved and synced."
    } catch {
        Write-Log "Cleanup failed during safety backup: $($_.Exception.Message)" "ERROR"
    }
}

# --------------------------------------------------------------------------
# MAIN MENU INTERFACE
# --------------------------------------------------------------------------

Get-AdminStatus
Clear-Host
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "    BitLocker Master Management Utility   " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "1. Run Full System Audit"
Write-Host "2. Sync/Generate Recovery Key to AD"
Write-Host "3. Cleanup Redundant Protectors"
Write-Host "4. Exit"
Write-Host " "

$Choice = Read-Host "Select an option (1-4)"

switch ($Choice) {
    "1" { Invoke-BitLockerAudit }
    "2" { Invoke-KeySync }
    "3" { Invoke-ProtectorCleanup }
    "4" { Write-Log "User exited utility."; exit 5 }
    Default { Write-Host "Invalid Selection."; exit 5 }
}
