#requires -Version 5.1

<#
.SYNOPSIS
    Searches for locked-out Active Directory user accounts and unlocks them.

.DESCRIPTION
    Queries Active Directory for all currently locked-out user accounts using the ActiveDirectory module.
    Displays discovered locked accounts, logs details to C:\Temp, and unlocks the accounts with native
    SupportsShouldProcess capabilities (-WhatIf and -Confirm supported). Automatically performs 7-day log maintenance.

.PARAMETER LogDirectory
    The local directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Unlock-ADLockedAccounts.ps1 -WhatIf

.EXAMPLE
    .\Unlock-ADLockedAccounts.ps1 -Confirm:$false

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: RSAT Active Directory Tools module, Domain Administrator or Delegated User Rights.
    Change Log   :
        1.0 - Initial sanitized production release.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Specify the directory for execution log storage.")]
    [ValidateNotNullOrEmpty()]
    [string]$LogDirectory = "C:\Temp"
)

# --------------------------------------------------------------------------
# 1. PREREQUISITES & PRIVILEGE CHECKS
# --------------------------------------------------------------------------
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Warning "Running in non-elevated context. Ensure proper Domain delegated rights to unlock accounts."
}

$RequiredModule = "ActiveDirectory"

if (-not (Get-Module -ListAvailable -Name $RequiredModule)) {
    Write-Host "Required module '$RequiredModule' was not found. Attempting installation for CurrentUser..." -ForegroundColor Yellow
    try {
        Install-Module -Name $RequiredModule -Scope CurrentUser -AllowClobber -Force -ErrorAction Stop
        Write-Host "Successfully installed '$RequiredModule'." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to install required module '$RequiredModule': $($_.Exception.Message)"
        exit 1
    }
}

Import-Module -Name $RequiredModule -ErrorAction Stop

# --------------------------------------------------------------------------
# 2. LOGGING INITIALIZATION & HOUSEKEEPING
# --------------------------------------------------------------------------
$ScriptName = "AD_UnlockAccounts"
$DateStamp  = Get-Date -Format "yyyyMMdd_HHmmss"

if (-not (Test-Path -Path $LogDirectory)) {
    New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
}

# Log rotation: Remove log files older than 7 days from C:\Temp
Get-ChildItem -Path $LogDirectory -Filter "*.log" -File -ErrorAction SilentlyContinue | 
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } | 
    Remove-Item -Force -ErrorAction SilentlyContinue

$LogFile = Join-Path -Path $LogDirectory -ChildPath "$($ScriptName)_$($DateStamp).log"

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )
    $LogEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] - $Message"
    $LogEntry | Out-File -FilePath $LogFile -Append -Encoding utf8
    
    $Color = switch ($Level) {
        "ERROR" { "Red" }
        "WARN"  { "Yellow" }
        Default { "Cyan" }
    }
    Write-Host $LogEntry -ForegroundColor $Color
}

# --------------------------------------------------------------------------
# 3. SCRIPT EXECUTION
# --------------------------------------------------------------------------
try {
    Write-Log "Searching Active Directory for locked-out user accounts..." "INFO"

    $LockedAccounts = Search-ADAccount -LockedOut -ErrorAction Stop

    if (-not $LockedAccounts) {
        Write-Log "No locked-out Active Directory user accounts were found." "INFO"
        return
    }

    Write-Log "Found $($LockedAccounts.Count) locked-out account(s)." "WARN"

    foreach ($Account in $LockedAccounts) {
        Write-Log "Target Account: $($Account.SamAccountName) ($($Account.Name))" "INFO"
        
        if ($PSCmdlet.ShouldProcess($Account.SamAccountName, "Unlock Active Directory Account")) {
            try {
                Unlock-ADAccount -Identity $Account -ErrorAction Stop
                Write-Log "SUCCESS: Unlocked account '$($Account.SamAccountName)'." "INFO"
                
                [PSCustomObject]@{
                    SamAccountName = $Account.SamAccountName
                    Name           = $Account.Name
                    Status         = "Unlocked"
                    Timestamp      = Get-Date
                }
            }
            catch {
                Write-Log "FAILED to unlock account '$($Account.SamAccountName)': $($_.Exception.Message)" "ERROR"
            }
        }
    }
}
catch {
    Write-Log "CRITICAL ERROR while searching or unlocking accounts: $($_.Exception.Message)" "ERROR"
    exit 1
}