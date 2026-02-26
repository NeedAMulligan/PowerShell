<#
.SYNOPSIS
    Master BitLocker Management Utility for Local Systems.
.DESCRIPTION
    A modular script for BitLocker administration. Securely handles recovery data 
    by ensuring the 48-digit Recovery Password is NEVER written to local logs, 
    while still providing console output for documentation purposes.
.PARAMETER Interactive
    Allows for menu selection and pop-up alerts. Defaults to true.
.EXITCODES
    0 - Success
    1 - Missing Administrative Privileges
    2 - TPM/Hardware Requirement Not Met
    3 - BitLocker/Encryption Error
    4 - Active Directory Sync Error
    5 - User Aborted or Invalid Selection
#>

[CmdletBinding()]
param([switch]$Interactive = $true)

# --------------------------------------------------------------------------
# VARIABLES & INITIALIZATION
# --------------------------------------------------------------------------
$Config = @{
    ScriptName = "BitLocker-Master-Util"
    LogPath    = "C:\temp"
    Timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
}

$LogFile = Join-Path $Config.LogPath "$($Config.ScriptName)_$($Config.Timestamp).log"

if (!(Test-Path $Config.LogPath)) { 
    New-Item -ItemType Directory -Path $Config.LogPath -Force | Out-Null 
}

# --------------------------------------------------------------------------
# SHARED FUNCTIONS
# --------------------------------------------------------------------------

function Write-SecureOutput {
    param(
        [Parameter(Mandatory=$true)] [string]$Message, 
        [ValidateSet("INFO", "WARN", "ERROR", "AUDIT", "SUCCESS")] [string]$Level = "INFO",
        [bool]$LogToFile = $true
    )
    $Timestamp = Get-Date -Format "HH:mm:ss"
    $FullMessage = "[$Timestamp] [$Level] - $Message"
    
    # Determine Console Color
    $Color = switch($Level) { 
        "WARN"    {"Yellow"} 
        "ERROR"   {"Red"} 
        "AUDIT"   {"Green"} 
        "SUCCESS" {"Cyan"} 
        Default   {"White"} 
    }

    # ALWAYS write to console for documentation capture
    Write-Host $FullMessage -ForegroundColor $Color 

    # ONLY write to file if it's not sensitive info
    if ($LogToFile) {
        $FullMessage | Out-File -FilePath $LogFile -Append
    }
}

function Test-AdminStatus {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-SecureOutput "Critical: Administrator privileges required." "ERROR"
        exit 1
    }
}

# --------------------------------------------------------------------------
# FEATURE MODULES
# --------------------------------------------------------------------------

function Invoke-BitLockerAudit {
    Write-SecureOutput "Starting System Audit..." "AUDIT"
    try {
        $TPM = Get-Tpm
        $Vol = Get-BitLockerVolume -MountPoint "C:"
        
        $AuditSummary = @"

--- AUDIT RESULTS ---
TPM Present: $($TPM.TpmPresent)
Encryption:  $($Vol.EncryptionMethod)
Status:      $($Vol.ProtectionStatus)
---------------------
"@
        Write-SecureOutput $AuditSummary "AUDIT"
    } catch {
        Write-SecureOutput "Audit Failed: $($_.Exception.Message)" "ERROR"
    }
}

function Invoke-KeySync {
    Write-SecureOutput "Initiating AD Key Sync..." "INFO"
    try {
        $Vol = Get-BitLockerVolume -MountPoint "C:"
        $Protectors = $Vol.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }
        
        if ($null -eq $Protectors) {
            Write-SecureOutput "No Recovery Password found. Adding protector..." "WARN"
            Add-BitLockerKeyProtector -MountPoint "C:" -RecoveryPasswordProtector | Out-Null
            $Vol = Get-BitLockerVolume -MountPoint "C:"
            $Protectors = $Vol.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }
        }

        $TargetID = $Protectors[0].KeyProtectorId
        
        # Action: Backup to AD
        Backup-BitLockerKeyProtector -MountPoint "C:" -KeyProtectorId $TargetID -ErrorAction Stop
        
        # DOCUMENTATION: We print the ID to console so it can be captured, 
        # but we do NOT save this specific line to the log file.
        Write-SecureOutput "SUCCESS: Recovery ID [$TargetID] backed up to AD." "SUCCESS" -LogToFile $false
        Write-SecureOutput "Backup confirmation saved to system event logs." "INFO"

    } catch {
        Write-SecureOutput "Sync Failed: $($_.Exception.Message)" "ERROR"
        exit 4
    }
}

function Invoke-ProtectorCleanup {
    Write-SecureOutput "Starting Protector Cleanup..." "INFO"
    $Protectors = (Get-BitLockerVolume -MountPoint "C:").KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }
    
    if ($Protectors.Count -le 1) {
        Write-SecureOutput "No redundant protectors found." "INFO"
        return
    }

    $LatestID = $Protectors[-1].KeyProtectorId
    $OldIDs = $Protectors[0..($Protectors.Count - 2)] | Select-Object -ExpandProperty KeyProtectorId

    try {
        Write-SecureOutput "Verifying backup for ID: $LatestID" "INFO" -LogToFile $false
        Backup-BitLockerKeyProtector -MountPoint "C:" -KeyProtectorId $LatestID -ErrorAction Stop
        
        foreach ($ID in $OldIDs) {
            Write-SecureOutput "Removing Old Protector ID: $ID" "WARN" -LogToFile $false
            Remove-BitLockerKeyProtector -MountPoint "C:" -KeyProtectorId $ID
        }
    } catch {
        Write-SecureOutput "Cleanup aborted: $($_.Exception.Message)" "ERROR"
        exit 3
    }
}

# --------------------------------------------------------------------------
# MAIN EXECUTION
# --------------------------------------------------------------------------

Test-AdminStatus
Clear-Host
Write-Host "--- BitLocker Local Management ---" -ForegroundColor Cyan
Write-Host "1. Run Audit`n2. Sync to AD`n3. Cleanup`n4. Exit"

$Choice = Read-Host "Selection"
switch ($Choice) {
    "1" { Invoke-BitLockerAudit }
    "2" { Invoke-KeySync }
    "3" { Invoke-ProtectorCleanup }
    "4" { exit 0 }
    Default { exit 5 }
}
