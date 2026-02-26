<#
.SYNOPSIS
    Enforces the 'AllSigned' Execution Policy on the local machine.

.DESCRIPTION
    This script transitions the workstation from 'RemoteSigned' or 'Bypass' 
    to 'AllSigned'. This ensures only scripts digitally signed by a trusted 
    certificate (like your SharePoint/Code Signing cert) can execute.

.PARAMETER PolicyLevel
    The execution policy to apply. Defaults to 'AllSigned'.

.EXAMPLE
    .\Set-LocalSecurityPolicy.ps1
#>

# -------------------------------------------------------------------------
# VARIABLES
# -------------------------------------------------------------------------
$DesiredPolicy   = "AllSigned"
$LogPath         = "C:\temp"
$Timestamp       = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile         = Join-Path $LogPath "SecurityPolicy_$($Timestamp).log"

# -------------------------------------------------------------------------
# HELPER FUNCTIONS
# -------------------------------------------------------------------------
function Write-Log {
    param([string]$Message, [ValidateSet("INFO", "WARN", "ERROR")] $Level = "INFO")
    $Stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Line = "[$Stamp] [$Level] $Message"
    $Line | Out-File -FilePath $LogFile -Append
    Write-Host $Line
}

function Test-Admin {
    $User = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Role = [Security.Principal.WindowsBuiltInRole]::Administrator
    return (New-Object Security.Principal.WindowsPrincipal($User)).IsInRole($Role)
}

# -------------------------------------------------------------------------
# MAIN LOGIC
# -------------------------------------------------------------------------
try {
    if (-not (Test-Path $LogPath)) { New-Item $LogPath -ItemType Directory -Force | Out-Null }
    Write-Log "Initializing Security Policy Hardening..."

    # 1. Pre-flight Check: Admin Rights
    if (-not (Test-Admin)) {
        Write-Log "ERROR: Administrator privileges required to change Execution Policy." "ERROR"
        exit 1
    }

    # 2. Apply the Policy
    Write-Log "Setting Execution Policy to '$DesiredPolicy' for LocalMachine..."
    Set-ExecutionPolicy -ExecutionPolicy $DesiredPolicy -Scope LocalMachine -Force

    # 3. Verify the Change
    $CurrentPolicy = Get-ExecutionPolicy -Scope LocalMachine
    if ($CurrentPolicy -eq $DesiredPolicy) {
        Write-Log "SUCCESS: System is now protected by '$DesiredPolicy' policy."
        Write-Host "`n--- SECURITY HARDENING COMPLETE ---" -ForegroundColor Green
        Write-Host "Current Policy: $CurrentPolicy"
        Write-Host "Unsigned scripts will now be blocked by default."
    }
    else {
        Write-Log "ERROR: Verification failed. Policy is currently: $CurrentPolicy" "ERROR"
        exit 3
    }

    exit 0
}
catch {
    Write-Log "FATAL ERROR: $($_.Exception.Message)" "ERROR"
    exit 99
}
