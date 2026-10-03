#requires -Version 5.1

<#
.SYNOPSIS
    Exports last logon timestamp information for active domain users to a CSV report.

.DESCRIPTION
    Queries Active Directory for enabled user accounts, converts the LastLogonTimeStamp attribute 
    into a human-readable date-time format, and exports the results to a CSV file.
    Logs execution activity to C:\Temp\ and automatically cleans up log files older than 7 days.

.PARAMETER ExportPath
    The target file path where the exported CSV report will be saved. Defaults to 'C:\Temp\LastLogon.csv'.

.PARAMETER LogDirectory
    The local directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Export-ADUserLastLogon.ps1

.EXAMPLE
    .\Export-ADUserLastLogon.ps1 -ExportPath "C:\Temp\UserLogonReport.csv" -LogDirectory "C:\Temp"

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: RSAT Active Directory Tools module, Domain Administrator or User privileges.
    Change Log   :
        1.0 - Initial sanitized production release.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0, HelpMessage = "Specify the target CSV export path.")]
    [ValidateNotNullOrEmpty()]
    [string]$ExportPath = "C:\Temp\LastLogon.csv",

    [Parameter(Mandatory = $false, HelpMessage = "Specify the directory for execution log storage.")]
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
$ScriptName = "AD_UserLastLogon"
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
    Write-Log "Querying Active Directory for enabled user accounts..." "INFO"

    $ADUsers = Get-ADUser -Filter { Enabled -eq $true } -Properties LastLogonTimeStamp -ErrorAction Stop

    Write-Log "Retrieved $($ADUsers.Count) enabled user account(s). Processing last logon timestamps..." "INFO"

    $Results = foreach ($User in $ADUsers) {
        $StampFormatted = if ($User.LastLogonTimeStamp) {
            [DateTime]::FromFileTime($User.LastLogonTimeStamp).ToString('yyyy-MM-dd_HH:mm:ss')
        }
        else {
            "Never"
        }

        [PSCustomObject]@{
            Name  = $User.Name
            Stamp = $StampFormatted
        }
    }

    $ExportDirectory = Split-Path -Path $ExportPath -Parent
    if (-not (Test-Path -Path $ExportDirectory)) {
        New-Item -Path $ExportDirectory -ItemType Directory -Force | Out-Null
    }

    $Results | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding utf8
    Write-Log "Successfully exported $($Results.Count) user record(s) to: $ExportPath" "INFO"
}
catch {
    Write-Log "CRITICAL ERROR while querying or exporting Active Directory data: $($_.Exception.Message)" "ERROR"
    exit 1
}