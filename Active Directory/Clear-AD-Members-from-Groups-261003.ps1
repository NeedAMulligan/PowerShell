#requires -Version 5.1

<#
.SYNOPSIS
    Removes all Active Directory group memberships for user accounts located in a target Organizational Unit.

.DESCRIPTION
    Queries Active Directory user accounts within a specified Search Base (e.g., a Disabled Users OU), 
    enumerates their current group memberships (excluding Primary Group membership), and removes each user 
    from those groups. Includes native -WhatIf/-Confirm safety controls, execution logging in C:\Temp, 
    and automatic 7-day log maintenance.

.PARAMETER SearchBase
    The Distinguished Name (DN) of the Organizational Unit (OU) or container holding target user accounts.

.PARAMETER LogDirectory
    The local directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Remove-ADUserGroupMemberships.ps1 -SearchBase "OU=Disabled Users,DC=contoso,DC=com" -WhatIf

.EXAMPLE
    .\Remove-ADUserGroupMemberships.ps1 -SearchBase "OU=2023,OU=Disabled Users,DC=contoso,DC=com" -Confirm:$false

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: RSAT Active Directory Tools module, Domain Administrator or Delegated Rights to modify group memberships.
    Change Log   :
        1.0 - Initial sanitized production release.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Specify the Distinguished Name (DN) search base context.")]
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
$ScriptName = "AD_RemoveUserGroupMemberships"
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
    Write-Log "Querying Active Directory user accounts in Search Base: $SearchBase" "INFO"

    $TargetUsers = Get-ADUser -Filter * -SearchBase $SearchBase -Properties MemberOf -ErrorAction Stop

    if (-not $TargetUsers -or $TargetUsers.Count -eq 0) {
        Write-Log "No user accounts found in the specified Search Base context." "WARN"
        return
    }

    Write-Log "Found $($TargetUsers.Count) user account(s). Processing group removals..." "INFO"

    foreach ($User in $TargetUsers) {
        $UserDN = $User.DistinguishedName
        $SamAccountName = $User.SamAccountName
        $Groups = $User.MemberOf

        if (-not $Groups -or $Groups.Count -eq 0) {
            Write-Log "User '$SamAccountName' has no additional group memberships to remove." "INFO"
            continue
        }

        Write-Log "Processing $($Groups.Count) group membership(s) for user '$SamAccountName'..." "INFO"

        foreach ($GroupDN in $Groups) {
            if ($PSCmdlet.ShouldProcess("Group: $GroupDN", "Remove Member: $SamAccountName")) {
                try {
                    Remove-ADGroupMember -Identity $GroupDN -Members $UserDN -Confirm:$false -ErrorAction Stop
                    Write-Log "SUCCESS: Removed user '$SamAccountName' from group '$GroupDN'." "INFO"
                }
                catch {
                    Write-Log "ERROR: Failed to remove user '$SamAccountName' from group '$GroupDN': $($_.Exception.Message)" "ERROR"
                }
            }
        }
    }

    Write-Log "Group membership removal process completed." "INFO"
}
catch {
    Write-Log "CRITICAL ERROR during execution: $($_.Exception.Message)" "ERROR"
    exit 1
}