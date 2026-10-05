#requires -Version 5.1

<#
.SYNOPSIS
    Identifies inactive Active Directory computer accounts, updates their description, disables them, and moves them to a target OU.

.DESCRIPTION
    Queries Active Directory for computer accounts that have been inactive for a specified number of days (based on lastLogonTimestamp).
    Updates each account's description attribute with a timestamped disable reason, disables the computer account, and 
    relocates the object to a designated destination Organizational Unit (OU). Includes native -WhatIf/-Confirm safety 
    controls, execution logging in C:\Temp, and automatic 7-day log cleanup.

.PARAMETER SearchBase
    The Distinguished Name (DN) of the Organizational Unit (OU) or container to query for inactive computer accounts.

.PARAMETER DestinationBase
    The Distinguished Name (DN) of the target Organizational Unit (OU) where disabled computer accounts will be moved.

.PARAMETER DaysInactive
    The threshold number of days an account must be inactive before processing. Defaults to 60 days.

.PARAMETER LogDirectory
    The directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Disable-InactiveADComputers.ps1 -SearchBase "OU=Workstations,DC=contoso,DC=com" -DestinationBase "OU=Disabled Computers,DC=contoso,DC=com" -WhatIf

.EXAMPLE
    .\Disable-InactiveADComputers.ps1 -SearchBase "OU=AllComputers,DC=contoso,DC=com" -DestinationBase "OU=Disabled,DC=contoso,DC=com" -DaysInactive 90 -Confirm:$false

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: RSAT Active Directory Tools module, Domain Administrator or Delegated Rights to modify/move computer objects.
    Change Log   :
        1.0 - Initial sanitized production release (Migrated from Quest ActiveRoles to native ActiveDirectory module).
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Specify Search Base DN context for inactive computers.")]
    [ValidateNotNullOrEmpty()]
    [string]$SearchBase,

    [Parameter(Mandatory = $true, Position = 1, HelpMessage = "Specify Destination Base DN context for disabled computers.")]
    [ValidateNotNullOrEmpty()]
    [string]$DestinationBase,

    [Parameter(Mandatory = $false, HelpMessage = "Number of inactive days threshold.")]
    [ValidateRange(1, 3650)]
    [int]$DaysInactive = 60,

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
$ScriptName = "AD_DisableInactiveComputers"
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
    $CutoffDate = (Get-Date).AddDays(-$DaysInactive)
    $TodayString = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Description = "Account disabled due to inactivity on $TodayString"

    Write-Log "Searching for computer accounts inactive since $CutoffDate ($DaysInactive days)..." "INFO"
    Write-Log "Search Base: $SearchBase" "INFO"
    Write-Log "Destination Base: $DestinationBase" "INFO"

    $InactiveComputers = Get-ADComputer -Filter { Enabled -eq $true -and LastLogonTimeStamp -lt $CutoffDate.ToFileTime() } -SearchBase $SearchBase -Properties LastLogonTimeStamp, Description -ErrorAction Stop

    if (-not $InactiveComputers -or $InactiveComputers.Count -eq 0) {
        Write-Log "No inactive computer accounts matching criteria were found." "WARN"
        return
    }

    Write-Log "Found $($InactiveComputers.Count) inactive computer account(s). Processing actions..." "INFO"

    foreach ($Computer in $InactiveComputers) {
        $ComputerName = $Computer.Name
        $ComputerDN   = $Computer.DistinguishedName

        if ($PSCmdlet.ShouldProcess($ComputerName, "Disable, update description, and move to '$DestinationBase'")) {
            try {
                # 1. Update Description
                Set-ADComputer -Identity $ComputerDN -Description $Description -ErrorAction Stop
                Write-Log "SUCCESS: Updated description for '$ComputerName'." "INFO"

                # 2. Disable Computer Account
                Disable-ADAccount -Identity $ComputerDN -ErrorAction Stop
                Write-Log "SUCCESS: Disabled computer account '$ComputerName'." "INFO"

                # 3. Move Computer Object
                Move-ADObject -Identity $ComputerDN -TargetPath $DestinationBase -ErrorAction Stop
                Write-Log "SUCCESS: Moved computer '$ComputerName' to '$DestinationBase'." "INFO"
            }
            catch {
                Write-Log "ERROR processing computer '$ComputerName': $($_.Exception.Message)" "ERROR"
            }
        }
    }

    Write-Log "Inactive computer account maintenance complete." "INFO"
}
catch {
    Write-Log "CRITICAL ERROR during execution: $($_.Exception.Message)" "ERROR"
    exit 1
}