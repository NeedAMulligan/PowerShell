#requires -Version 5.1

<#
.SYNOPSIS
    Deletes Active Directory user accounts within a specified Organizational Unit (OU).

.DESCRIPTION
    Queries Active Directory for user accounts located within a designated target Search Base OU 
    and removes them. Includes native -WhatIf/-Confirm safety controls, execution logging in C:\Temp, 
    and automatic 7-day log maintenance.

.PARAMETER SearchBase
    The Distinguished Name (DN) of the Organizational Unit (OU) or container containing user accounts to be deleted.

.PARAMETER LogDirectory
    The local directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Remove-ADUsersFromOU.ps1 -SearchBase "OU=Disabled Users,DC=contoso,DC=com" -WhatIf

.EXAMPLE
    .\Remove-ADUsersFromOU.ps1 -SearchBase "OU=2023,OU=Disabled Users,DC=contoso,DC=com" -Confirm:$false

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: RSAT Active Directory Tools module, Domain Administrator or Delegated Rights to delete user objects.
    Change Log   :
        1.0 - Initial sanitized production release.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Specify Distinguished Name (DN) search base context for accounts to delete.")]
    [ValidateNotNullOrEmpty()]
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
$ScriptName = "AD_RemoveUserAccounts"
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
    Write-Log "Searching for user accounts to remove in Search Base: $SearchBase" "INFO"

    $TargetUsers = Get-ADUser -SearchBase $SearchBase -Filter * -ErrorAction Stop

    if (-not $TargetUsers -or $TargetUsers.Count -eq 0) {
        Write-Log "No Active Directory user accounts were found in specified Search Base." "WARN"
        return
    }

    Write-Log "Discovered $($TargetUsers.Count) user account(s) targeted for removal." "INFO"

    $SuccessCount = 0
    $FailureCount = 0

    foreach ($User in $TargetUsers) {
        $SamAccountName = $User.SamAccountName
        $UserDN         = $User.DistinguishedName

        if ($PSCmdlet.ShouldProcess($SamAccountName, "Delete Active Directory User ($UserDN)")) {
            try {
                Remove-ADUser -Identity $UserDN -Confirm:$false -ErrorAction Stop
                Write-Log "SUCCESS: Removed user account '$SamAccountName' ($UserDN)." "INFO"
                $SuccessCount++
            }
            catch {
                Write-Log "ERROR: Failed to remove user account '$SamAccountName': $($_.Exception.Message)" "ERROR"
                $FailureCount++
            }
        }
    }

    Write-Log "Account removal process complete. Successful: $SuccessCount | Failed: $FailureCount" "INFO"
}
catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
    Write-Log "ERROR: The specified Search Base '$SearchBase' was not found in Active Directory." "ERROR"
    exit 1
}
catch {
    Write-Log "CRITICAL ERROR during execution: $($_.Exception.Message)" "ERROR"
    exit 1
}