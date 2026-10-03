#requires -Version 5.1

<#
.SYNOPSIS
    Configures user account password policy flags (Password Never Expires and Change Password at Next Logon).

.DESCRIPTION
    Queries Active Directory user accounts within a specified Search Base or across the domain,
    sets 'PasswordNeverExpires' to $false, and requires users to change their password at next logon.
    Includes native -WhatIf/-Confirm safety controls, execution logging in C:\Temp, and 7-day log cleanup.

.PARAMETER SearchBase
    The Distinguished Name (DN) of the Organizational Unit (OU) or container to query.
    If omitted, queries user accounts across the entire domain.

.PARAMETER PasswordNeverExpires
    Sets whether user passwords never expire. Defaults to $false.

.PARAMETER ChangePasswordAtLogon
    Sets whether users must change their password at next logon. Defaults to $true.

.PARAMETER LogDirectory
    The directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Set-ADUserPasswordPolicy.ps1 -SearchBase "OU=Employees,DC=contoso,DC=com" -WhatIf

.EXAMPLE
    .\Set-ADUserPasswordPolicy.ps1 -SearchBase "OU=Users,DC=contoso,DC=com" -PasswordNeverExpires $false -ChangePasswordAtLogon $true -Confirm:$false

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: RSAT Active Directory Tools module, Domain Administrator or Delegated Rights to modify user objects.
    Change Log   :
        1.0 - Initial sanitized production release.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $false, Position = 0, HelpMessage = "Specify Distinguished Name (DN) search base context.")]
    [string]$SearchBase,

    [Parameter(Mandatory = $false, HelpMessage = "Specify whether user passwords never expire.")]
    [bool]$PasswordNeverExpires = $false,

    [Parameter(Mandatory = $false, HelpMessage = "Specify whether users must change password at next logon.")]
    [bool]$ChangePasswordAtLogon = $true,

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
$ScriptName = "AD_SetPasswordPolicy"
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
        ErrorAction = "Stop"
    }

    if ([string]::IsNullOrWhiteSpace($SearchBase)) {
        Write-Log "Searching for user accounts across the entire domain..." "INFO"
    }
    else {
        Write-Log "Searching for user accounts in Search Base: $SearchBase" "INFO"
        $QueryParams.Add("SearchBase", $SearchBase)
    }

    $ADUsers = Get-ADUser @QueryParams

    if (-not $ADUsers -or $ADUsers.Count -eq 0) {
        Write-Log "No Active Directory user accounts found in specified scope." "WARN"
        return
    }

    Write-Log "Found $($ADUsers.Count) user account(s). Processing password policy modifications..." "INFO"

    foreach ($User in $ADUsers) {
        $SamAccountName = $User.SamAccountName
        Write-Log "Processing user account: $SamAccountName" "INFO"

        if ($PSCmdlet.ShouldProcess($SamAccountName, "Set PasswordNeverExpires=$PasswordNeverExpires and ChangePasswordAtLogon=$ChangePasswordAtLogon")) {
            try {
                Set-ADUser -Identity $User.DistinguishedName -PasswordNeverExpires $PasswordNeverExpires -ChangePasswordAtLogon $ChangePasswordAtLogon -ErrorAction Stop
                Write-Log "SUCCESS: Password policy updated for '$SamAccountName'." "INFO"
            }
            catch {
                Write-Log "ERROR: Failed to update password policy for '$SamAccountName': $($_.Exception.Message)" "ERROR"
            }
        }
    }

    Write-Log "User password policy configuration complete." "INFO"
}
catch {
    Write-Log "CRITICAL ERROR during user password policy processing: $($_.Exception.Message)" "ERROR"
    exit 1
}