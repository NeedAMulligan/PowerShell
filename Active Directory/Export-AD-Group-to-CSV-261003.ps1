#requires -Version 5.1

<#
.SYNOPSIS
    Exports members of a specified Active Directory group to a CSV report.

.DESCRIPTION
    Queries Active Directory for members of a targeted group using the ActiveDirectory module.
    Outputs member properties to a structured CSV file, writes execution logs to C:\Temp,
    and automatically cleans up log files older than 7 days.

.PARAMETER GroupName
    The Identity (Name, SamAccountName, or DistinguishedName) of the target Active Directory group.

.PARAMETER ExportPath
    The file path where the exported CSV report will be written. Defaults to 'C:\Temp\AD_GroupMembers_<GroupName>_<DateStamp>.csv'.

.PARAMETER LogDirectory
    The directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Export-ADGroupMembersToCsv.ps1 -GroupName "Domain Admins"

.EXAMPLE
    .\Export-ADGroupMembersToCsv.ps1 -GroupName "VPN_Users" -ExportPath "C:\Temp\VPN_Members.csv" -LogDirectory "C:\Temp"

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: RSAT Active Directory Tools module, Domain User or Administrative privileges.
    Change Log   :
        1.0 - Initial sanitized production release.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Specify the target Active Directory group identity.")]
    [ValidateNotNullOrEmpty()]
    [string]$GroupName,

    [Parameter(Mandatory = $false, HelpMessage = "Specify target CSV output file path.")]
    [string]$ExportPath,

    [Parameter(Mandatory = $false, HelpMessage = "Specify directory for execution log storage.")]
    [ValidateNotNullOrEmpty()]
    [string]$LogDirectory = "C:\Temp"
)

# --------------------------------------------------------------------------
# 1. PREREQUISITES & MODULE CHECKS
# --------------------------------------------------------------------------
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Warning "Running in non-elevated context. Ensure proper Domain User rights to query Active Directory."
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
$ScriptName = "AD_ExportGroupMembers"
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
    # Set default ExportPath dynamically if not provided
    if ([string]::IsNullOrWhiteSpace($ExportPath)) {
        $SafeGroupName = $GroupName -replace '[^a-zA-Z0-9_-]', '_'
        $ExportPath = Join-Path -Path $LogDirectory -ChildPath "AD_GroupMembers_${SafeGroupName}_${DateStamp}.csv"
    }

    Write-Log "Querying Active Directory for members of group '$GroupName'..." "INFO"

    $GroupMembers = Get-ADGroupMember -Identity $GroupName -ErrorAction Stop

    if (-not $GroupMembers -or $GroupMembers.Count -eq 0) {
        Write-Log "The Active Directory group '$GroupName' was found, but contains no members." "WARN"
        return
    }

    Write-Log "Retrieved $($GroupMembers.Count) member(s) from group '$GroupName'. Exporting to CSV..." "INFO"

    $ExportDirectory = Split-Path -Path $ExportPath -Parent
    if (-not (Test-Path -Path $ExportDirectory)) {
        New-Item -Path $ExportDirectory -ItemType Directory -Force | Out-Null
    }

    $GroupMembers | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding utf8
    Write-Log "SUCCESS! Exported group member details to: $ExportPath" "INFO"
}
catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
    Write-Log "ERROR: The Active Directory group '$GroupName' was not found." "ERROR"
    exit 1
}
catch {
    Write-Log "CRITICAL ERROR during group member export execution: $($_.Exception.Message)" "ERROR"
    exit 1
}