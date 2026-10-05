#requires -Version 5.1

<#
.SYNOPSIS
    Audits Active Directory user account password status and expiration properties across the domain or targeted OU.

.DESCRIPTION
    Queries Active Directory user accounts to extract password policy details, including PasswordLastSet, 
    PasswordExpired, and PasswordNeverExpires attributes. Outputs structured objects directly to the pipeline, 
    supports optional CSV exporting, writes execution logs to C:\Temp, and performs automated 7-day log cleanup maintenance.

.PARAMETER SearchBase
    The Distinguished Name (DN) of the Organizational Unit (OU) or container to query.
    If omitted, queries user accounts across the entire domain.

.PARAMETER IncludeDisabled
    Switch parameter to include disabled user accounts in the query output. Defaults to active/enabled accounts only.

.PARAMETER ExportPath
    Optional CSV file path to export the password status audit report.

.PARAMETER LogDirectory
    The local directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Get-ADUserPasswordStatus.ps1

.EXAMPLE
    .\Get-ADUserPasswordStatus.ps1 -SearchBase "OU=Users,DC=contoso,DC=com" -IncludeDisabled

.EXAMPLE
    .\Get-ADUserPasswordStatus.ps1 -ExportPath "C:\Temp\PasswordStatusReport.csv"

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
$ScriptName = "AD_GetUserPasswordStatus"
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
        Properties  = @('PasswordLastSet', 'PasswordExpired', 'PasswordNeverExpires', 'Enabled')
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

    $Users = Get-ADUser @QueryParams

    if (-not $Users -or $Users.Count -eq 0) {
        Write-Log "No user accounts were found matching the specified criteria." "WARN"
        return
    }

    Write-Log "Retrieved $($Users.Count) user record(s). Formatting password policy details..." "INFO"

    $Results = $Users | Sort-Object Name | Select-Object Name, SamAccountName, PasswordLastSet, PasswordExpired, PasswordNeverExpires, Enabled

    if (-not [string]::IsNullOrWhiteSpace($ExportPath)) {
        $ExportDir = Split-Path -Path $ExportPath -Parent
        if ($ExportDir -and (-not (Test-Path -Path $ExportDir))) {
            New-Item -Path $ExportDir -ItemType Directory -Force | Out-Null
        }
        $Results | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding utf8
        Write-Log "SUCCESS: Exported $($Results.Count) user record(s) to: $ExportPath" "INFO"
    }

    # Pipeline output
    $Results
}
catch {
    Write-Log "CRITICAL ERROR during Active Directory password status audit execution: $($_.Exception.Message)" "ERROR"
    exit 1
}