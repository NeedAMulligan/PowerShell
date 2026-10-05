#requires -Version 5.1

<#
.SYNOPSIS
    Queries Active Directory for user accounts with expired passwords and outputs their password policy details.

.DESCRIPTION
    Audits Active Directory user accounts within a specified Search Base or across the entire domain 
    to locate accounts with expired passwords. Supports filtering by account enabled status, logs execution 
    activity to C:\Temp, and performs automated 7-day log cleanup maintenance.

.PARAMETER SearchBase
    The Distinguished Name (DN) of the Organizational Unit (OU) or container to query.
    If omitted, queries user accounts across the entire domain.

.PARAMETER IncludeDisabled
    Switch parameter to include disabled user accounts in the query output. Defaults to active/enabled accounts only.

.PARAMETER ExportPath
    Optional file path to export the expired password report to CSV format.

.PARAMETER LogDirectory
    The directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    Get-ADUserExpiredPasswords.ps1

.EXAMPLE
    Get-ADUserExpiredPasswords.ps1 -SearchBase "OU=Users,DC=contoso,DC=com" -IncludeDisabled

.EXAMPLE
    Get-ADUserExpiredPasswords.ps1 -ExportPath "C:\Temp\ExpiredPasswordsReport.csv"

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: RSAT Active Directory Tools module, Domain User privileges.
    Change Log   :
        1.0 - Initial sanitized production release.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0, HelpMessage = "Specify Distinguished Name (DN) search base context.")]
    [string]$SearchBase,

    [Parameter(Mandatory = $false, HelpMessage = "Include disabled user accounts in results.")]
    [switch]$IncludeDisabled,

    [Parameter(Mandatory = $false, HelpMessage = "Optional CSV output file path.")]
    [string]$ExportPath,

    [Parameter(Mandatory = $false, HelpMessage = "Specify directory for execution log storage.")]
    [ValidateNotNullOrEmpty()]
    [string]$LogDirectory = "C:\Temp"
)

# --------------------------------------------------------------------------
# 1. PREREQUISITES & PRIVILEGE CHECKS
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
$ScriptName = "Get_ADUserExpiredPasswords"
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
        Properties  = @("Enabled", "PasswordLastSet", "PasswordExpired", "PasswordNeverExpires")
        ErrorAction = "Stop"
    }

    if ($IncludeDisabled) {
        Write-Log "Querying Active Directory for all user accounts (including disabled)..." "INFO"
        $QueryParams.Add("Filter", "*")
    }
    else {
        Write-Log "Querying Active Directory for active/enabled user accounts..." "INFO"
        $QueryParams.Add("Filter", "Enabled -eq 'true'")
    }

    if ([string]::IsNullOrWhiteSpace($SearchBase)) {
        Write-Log "Searching across domain root..." "INFO"
    }
    else {
        Write-Log "Searching within Search Base context: $SearchBase" "INFO"
        $QueryParams.Add("SearchBase", $SearchBase)
    }

    $RawUsers = Get-ADUser @QueryParams

    if (-not $RawUsers -or $RawUsers.Count -eq 0) {
        Write-Log "No Active Directory user accounts were found in specified scope." "WARN"
        return
    }

    Write-Log "Retrieved $($RawUsers.Count) account(s). Filtering accounts with expired passwords..." "INFO"

    $ExpiredUsers = $RawUsers | 
        Where-Object { $_.PasswordExpired -eq $true } | 
        Sort-Object -Property Name | 
        Select-Object Name, SamAccountName, Enabled, PasswordLastSet, PasswordExpired, PasswordNeverExpires

    if (-not $ExpiredUsers) {
        Write-Log "No user accounts with expired passwords were found in the target scope." "INFO"
        return
    }

    Write-Log "Found $($ExpiredUsers.Count) user account(s) with expired passwords." "WARN"

    if (-not [string]::IsNullOrWhiteSpace($ExportPath)) {
        $ExportDir = Split-Path -Path $ExportPath -Parent
        if ($ExportDir -and (-not (Test-Path -Path $ExportDir))) {
            New-Item -Path $ExportDir -ItemType Directory -Force | Out-Null
        }
        $ExpiredUsers | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding utf8
        Write-Log "SUCCESS: Exported expired password report to: $ExportPath" "INFO"
    }

    # Pipeline output
    $ExpiredUsers
}
catch {
    Write-Log "CRITICAL ERROR during Active Directory query execution: $($_.Exception.Message)" "ERROR"
    exit 1
}