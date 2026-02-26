<#
.SYNOPSIS
    BitLocker Management Utility Library

.DESCRIPTION
    A robust utility library designed for local execution. Refactored to use CIM instances
    and advanced error handling for TPM and BitLocker volume management.

.PARAMETER Action
    The operation to perform: GetStatus, GetRecoveryKey, or TakeTPMOwnership.

.NOTES
    Log Path: C:\temp\BitLockerUtility_YYYYMMDD_HHMMSS.log
    Target: Local Workstation
#>

# --------------------------------------------------------------------------
# 1. VARIABLES & CONFIGURATION
# --------------------------------------------------------------------------
$Config = @{
    TargetDrive      = 'C:'
    LogDirectory     = 'C:\temp'
    MinFreePercent   = 10
    ScriptName       = "BitLockerUtility"
    Timestamp        = Get-Date -Format "yyyyMMdd_HHmmss"
}

$LogFile = Join-Path -Path $Config.LogDirectory -ChildPath "$($Config.ScriptName)_$($Config.Timestamp).log"

# --------------------------------------------------------------------------
# 2. LOGGING ENGINE
# --------------------------------------------------------------------------
function Write-LocalLog {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('INFO', 'WARNING', 'ERROR')][string]$Level = 'INFO'
    )
    $LogEntry = "[$($Config.Timestamp)] [$Level] - $Message"
    if (-not (Test-Path $Config.LogDirectory)) { New-Item -ItemType Directory -Path $Config.LogDirectory -Force | Out-Null }
    $LogEntry | Out-File -FilePath $LogFile -Append
    
    switch ($Level) {
        'INFO'    { Write-Host $LogEntry -ForegroundColor Cyan }
        'WARNING' { Write-Host $LogEntry -ForegroundColor Yellow }
        'ERROR'   { Write-Host $LogEntry -ForegroundColor Red }
    }
}

# --------------------------------------------------------------------------
# 3. PRE-FLIGHT CHECKS
# --------------------------------------------------------------------------
function Invoke-Preflight {
    Write-LocalLog "Initiating Pre-flight checks..."

    # Check Admin Rights
    $CurrentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($CurrentIdentity)
    if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-LocalLog "Access Denied: Please run as Administrator." -Level ERROR
        exit 2
    }

    # Check Disk Space
    $DriveInfo = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID = '$($Config.TargetDrive)'"
    $FreePercent = ($DriveInfo.FreeSpace / $DriveInfo.Size) * 100
    if ($FreePercent -lt $Config.MinFreePercent) {
        Write-LocalLog "Resource Failure: $($Config.TargetDrive) has only $([Math]::Round($FreePercent, 1))% free space." -Level ERROR
        exit 20
    }

    Write-LocalLog "Pre-flight checks passed successfully."
}

# --------------------------------------------------------------------------
# 4. CORE UTILITY FUNCTIONS
# --------------------------------------------------------------------------

function Get-LocalBitLockerStatus {
    try {
        Write-LocalLog "Querying BitLocker and TPM Status..."
        $Volume = Get-CimInstance -Namespace "ROOT\CIMV2\Security\MicrosoftVolumeEncryption" -ClassName Win32_EncryptableVolume -Filter "DriveLetter = '$($Config.TargetDrive)'"
        $Tpm = Get-CimInstance -Namespace "ROOT\CIMV2\Security\MicrosoftTpm" -ClassName Win32_Tpm
        
        if (-not $Tpm) { 
            Write-LocalLog "Hardware Warning: No TPM detected via CIM." -Level WARNING 
        }

        $Result = [PSCustomObject]@{
            Drive             = $Config.TargetDrive
            EncryptionStatus  = switch($Volume.GetProtectionStatus().ProtectionStatus){ 1{'Protected'} 0{'Unprotected'} default{'Unknown'} }
            PercentEncrypted  = "$($Volume.GetConversionStatus().EncryptionPercentage)%"
            TPM_Enabled       = if($Tpm){ $Tpm.IsEnabled().IsEnabled } else { $false }
            TPM_Owned         = if($Tpm){ $Tpm.IsOwned().IsOwned } else { $false }
        }
        return $Result
    }
    catch {
        Write-LocalLog "Status Query Failed: $($_.Exception.Message)" -Level ERROR
        exit 1
    }
}

function Get-LocalRecoveryKey {
    try {
        Write-LocalLog "Retrieving Numerical Recovery Passwords..."
        $Volume = Get-CimInstance -Namespace "ROOT\CIMV2\Security\MicrosoftVolumeEncryption" -ClassName Win32_EncryptableVolume -Filter "DriveLetter = '$($Config.TargetDrive)'"
        $ProtectorIDs = $Volume.GetKeyProtectors(3).VolumeKeyProtectorID # 3 = Numerical Password
        
        $Keys = foreach ($ID in $ProtectorIDs) {
            $KeyData = $Volume.GetKeyProtectorNumericalPassword($ID)
            [PSCustomObject]@{
                ID           = $ID
                RecoveryKey  = $KeyData.NumericalPassword
            }
        }
        return $Keys
    }
    catch {
        Write-LocalLog "Key Retrieval Failed: $($_.Exception.Message)" -Level ERROR
    }
}

function Set-TPMOwnership {
    try {
        $Tpm = Get-CimInstance -Namespace "ROOT\CIMV2\Security\MicrosoftTpm" -ClassName Win32_Tpm
        if (-not $Tpm) { throw "TPM hardware not found." }
        
        Write-LocalLog "Attempting to take TPM Ownership..."
        $Response = Invoke-CimMethod -InputObject $Tpm -MethodName "TakeOwnership"
        
        if ($Response.ReturnValue -eq 0) {
            Write-LocalLog "TPM Ownership successfully claimed."
        } else {
            Write-LocalLog "TPM Ownership failed. Error Code: $($Response.ReturnValue)" -Level ERROR
        }
    }
    catch {
        Write-LocalLog "TPM Operation Error: $($_.Exception.Message)" -Level ERROR
        exit 10
    }
}

# --------------------------------------------------------------------------
# 5. INTERACTIVE EXECUTION
# --------------------------------------------------------------------------
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('GetStatus', 'GetRecoveryKey', 'TakeOwnership')]
    $Action
)

Invoke-Preflight

switch ($Action) {
    'GetStatus'     { Get-LocalBitLockerStatus | Format-List; break }
    'GetRecoveryKey' { Get-LocalRecoveryKey | Format-Table -AutoSize; break }
    'TakeOwnership' { Set-TPMOwnership; break }
}

Write-LocalLog "Action '$Action' completed successfully."
exit 0
