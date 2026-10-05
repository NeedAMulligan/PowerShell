#requires -Version 5.1

<#
.SYNOPSIS
    Clears specified directory attributes for a single Active Directory user account.

.DESCRIPTION
    Retrieves a specified Active Directory user account and clears populated contact, organization, 
    and profile attributes (manager, home directory, telephone number, office address, title, department, 
    company, etc.). Includes native -WhatIf/-Confirm safety controls, execution logging in C:\Temp, 
    and automatic 7-day log maintenance.

.PARAMETER Identity
    The Identity (SamAccountName, DistinguishedName, UPN, or ObjectGUID) of the target Active Directory user account.

.PARAMETER AttributesToClear
    An array of Active Directory LDAP attribute names to clear from the user account.
    Defaults to standard offboarding attributes: manager, homeDirectory, homeDrive, physicalDeliveryOfficeName,
    telephoneNumber, o, postalCode, st, streetAddress, title, department, l, company, c.

.PARAMETER LogDirectory
    The local directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Clear-ADSingleUserAttributes.ps1 -Identity "jdoe" -WhatIf

.EXAMPLE
    .\Clear-ADSingleUserAttributes.ps1 -Identity "jdoe" -Confirm:$false

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: RSAT Active Directory Tools module, Domain Administrator or Delegated Rights to modify user objects.
    Change Log   :
        1.0 - Initial sanitized production release.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Specify the SamAccountName, DistinguishedName, or Identity of the target user.")]
    [ValidateNotNullOrEmpty()]
    [string]$Identity,

    [Parameter(Mandatory = $false, HelpMessage = "Specify an array of attribute names to clear from the user account.")]
    [string[]]$AttributesToClear = @(
        'manager',
        'homeDirectory',
        'homeDrive',
        'physicalDeliveryOfficeName',
        'telephoneNumber',
        'o',
        'postalCode',
        'st',
        'streetAddress',
        'title',
        'department',
        'l',
        'company',
        'c'
    ),

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
$ScriptName = "AD_ClearSingleUserAttributes"
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
    Write-Log "Searching for Active Directory user account: $Identity" "INFO"

    $User = Get-ADUser -Identity $Identity -ErrorAction Stop

    $SamAccountName = $User.SamAccountName
    $UserDN = $User.DistinguishedName

    Write-Log "Target user found: $SamAccountName ($UserDN)" "INFO"

    if ($PSCmdlet.ShouldProcess($SamAccountName, "Clear Attributes: $($AttributesToClear -join ', ')")) {
        try {
            Set-ADUser -Identity $UserDN -Clear $AttributesToClear -ErrorAction Stop
            Write-Log "SUCCESS: Cleared specified attributes for user '$SamAccountName'." "INFO"
        }
        catch {
            Write-Log "ERROR: Failed to clear attributes for user '$SamAccountName': $($_.Exception.Message)" "ERROR"
            exit 1
        }
    }

    Write-Log "Attribute cleanup process completed." "INFO"
}
catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
    Write-Log "ERROR: The specified Active Directory user account '$Identity' was not found." "ERROR"
    exit 1
}
catch {
    Write-Log "CRITICAL ERROR during execution: $($_.Exception.Message)" "ERROR"
    exit 1
}