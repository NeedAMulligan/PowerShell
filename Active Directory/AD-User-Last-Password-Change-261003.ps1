#requires -Version 5.1

<#
.SYNOPSIS
    Exports Active Directory user password metadata to a CSV report.

.DESCRIPTION
    Queries Active Directory user accounts within a specified Organizational Unit or Search Base, 
    extracts password last set dates, canonical names, and password expiration policy flags, 
    and exports the collected data to a structured CSV file. Includes standard logging to C:\Temp 
    and automatic cleanup of log files older than 7 days.

.PARAMETER SearchBase
    The Active Directory Distinguished Name (DN) of the Organizational Unit (OU) or container to query.
    If omitted, queries the entire domain.

.PARAMETER ExportPath
    The file path where the exported CSV report will be written. Defaults to 'C:\Temp\UserPasswordExport.csv'.

.PARAMETER LogDirectory
    The directory path where execution logs will be written. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Export-ADUserPasswordInfo.ps1

.EXAMPLE
    .\Export-ADUserPasswordInfo.ps1 -SearchBase "OU=Executive,OU=Employees,DC=contoso,DC=com" -ExportPath "C:\Temp\ExecPasswords.csv"

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: RSAT Active Directory Tools module, Domain User or Administrative privileges.
    Change Log   :
        1.0 - Initial sanitized production release.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0, HelpMessage = "Specify the Active Directory Search Base DN.")]
    [ValidateNotNullOrEmpty()]
    [string]$SearchBase,

    [Parameter(Mandatory = $false, HelpMessage = "Specify the target CSV output path.")]
    [ValidateNotNullOrEmpty()]
    [string]$ExportPath = "C:\Temp\UserPasswordExport.csv",

    [Parameter(Mandatory = $false, HelpMessage = "Specify the log directory path.")]
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
$ScriptName = "AD_UserPasswordExport"
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
        Filter     = "*"
        Properties = @("PasswordLastSet", "PasswordNeverExpires", "CanonicalName")
        ErrorAction = "Stop"
    }

    if ([string]::IsNullOrWhiteSpace($SearchBase)) {
        Write-Log "Querying Active Directory user password information across entire domain..." "INFO"
    }
    else {
        Write-Log "Querying Active Directory user password information in Search Base: $SearchBase" "INFO"
        $QueryParams.Add("SearchBase", $SearchBase)
    }

    $ADUsers = Get-ADUser @QueryParams

    Write-Log "Retrieved $($ADUsers.Count) user account(s). Processing records..." "INFO"

    $Results = $ADUsers | 
        Sort-Object -Property Name, CanonicalName | 
        Select-Object -Property Name, CanonicalName, PasswordLastSet, PasswordNeverExpires

    $ExportDirectory = Split-Path -Path $ExportPath -Parent
    if (-not (Test-Path -Path $ExportDirectory)) {
        New-Item -Path $ExportDirectory -ItemType Directory -Force | Out-Null
    }

    $Results | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding utf8
    Write-Log "Successfully exported $($Results.Count) user record(s) to: $ExportPath" "INFO"
}
catch {
    Write-Log "CRITICAL ERROR during Active Directory export: $($_.Exception.Message)" "ERROR"
    exit 1
}