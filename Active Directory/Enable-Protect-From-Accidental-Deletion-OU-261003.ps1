#requires -Version 5.1

<#
.SYNOPSIS
    Configures the 'ProtectedFromAccidentalDeletion' flag across Active Directory Organizational Units.

.DESCRIPTION
    Queries Active Directory for all Organizational Units (OUs) across the domain (including nested OUs)
    and enables or disables accidental deletion protection. Supports native -WhatIf dry-runs, outputs execution 
    logs to C:\Temp, and automatically removes log files older than 7 days.

.PARAMETER EnableProtection
    Specifies whether accidental deletion protection should be enabled ($true) or disabled ($false). Defaults to $true.

.PARAMETER SearchBase
    The Active Directory Distinguished Name (DN) of the root container or OU to scope the search. If omitted, queries the domain root.

.PARAMETER LogDirectory
    The directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Set-OUAccidentalDeletionProtection.ps1 -WhatIf

.EXAMPLE
    .\Set-OUAccidentalDeletionProtection.ps1 -EnableProtection $true -Confirm:$false

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: RSAT Active Directory Tools module, Domain Administrator or Delegated Rights to modify OUs.
    Change Log   :
        1.0 - Initial sanitized production release.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $false, Position = 0, HelpMessage = "Specify $true to enable protection or $false to disable.")]
    [bool]$EnableProtection = $true,

    [Parameter(Mandatory = $false, Position = 1, HelpMessage = "Specify Distinguished Name (DN) search base context.")]
    [string]$SearchBase,

    [Parameter(Mandatory = $false, HelpMessage = "Specify directory for execution log storage.")]
    [ValidateNotNullOrEmpty()]
    [string]$LogDirectory = "C:\Temp"
)

# --------------------------------------------------------------------------
# 1. PREREQUISITES & PRIVILEGE CHECKS
# --------------------------------------------------------------------------
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Error "This script requires administrative privileges. Please run PowerShell as Administrator."
    exit 1
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
$ScriptName = "AD_ProtectOUs"
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
    $QueryParams = @{
        Filter      = "*"
        Properties  = @("ProtectedFromAccidentalDeletion")
        ErrorAction = "Stop"
    }

    if ([string]::IsNullOrWhiteSpace($SearchBase)) {
        $SearchBase = (Get-ADDomain).DistinguishedName
        Write-Log "Searching for Organizational Units across domain root: $SearchBase" "INFO"
    }
    else {
        Write-Log "Searching for Organizational Units in Search Base: $SearchBase" "INFO"
        $QueryParams.Add("SearchBase", $SearchBase)
    }

    $OUs = Get-ADOrganizationalUnit @QueryParams

    if (-not $OUs -or $OUs.Count -eq 0) {
        Write-Log "No Organizational Units found in target scope." "WARN"
        return
    }

    Write-Log "Found $($OUs.Count) Organizational Unit(s). Setting ProtectedFromAccidentalDeletion to: $EnableProtection" "INFO"

    foreach ($OU in $OUs) {
        $OUPath = $OU.DistinguishedName
        $CurrentProtection = $OU.ProtectedFromAccidentalDeletion

        Write-Log "Processing OU: '$OUPath' (Current Protection: $CurrentProtection)" "INFO"

        if ($CurrentProtection -ne $EnableProtection) {
            if ($PSCmdlet.ShouldProcess($OUPath, "Set ProtectedFromAccidentalDeletion to '$EnableProtection'")) {
                try {
                    Set-ADOrganizationalUnit -Identity $OU.ObjectGUID -ProtectedFromAccidentalDeletion $EnableProtection -ErrorAction Stop
                    Write-Log "SUCCESS: Protection set to $EnableProtection for '$OUPath'." "INFO"
                }
                catch {
                    Write-Log "ERROR: Failed to update protection for '$OUPath': $($_.Exception.Message)" "ERROR"
                }
            }
        }
        else {
            Write-Log "  No change required. Protection is already set to $EnableProtection." "INFO"
        }
    }

    Write-Log "OU accidental deletion configuration complete." "INFO"
}
catch {
    Write-Log "CRITICAL ERROR during OU configuration: $($_.Exception.Message)" "ERROR"
    exit 1
}