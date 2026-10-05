#requires -Version 5.1

<#
.SYNOPSIS
    Retrieves the most recent account lockout event (Event ID 4740) from the Security Event Log.

.DESCRIPTION
    Queries the Security Event Log on the local computer or domain controller for the newest 
    account lockout event (Event ID 4740). Formats the event details and exports the output 
    to a timestamped report file in C:\Temp, while logging execution details and maintaining a 7-day log cleanup.

.PARAMETER ExportPath
    The file path where the lockout event details report will be saved. Defaults to 'C:\Temp\lockout.txt'.

.PARAMETER LogDirectory
    The directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Get-LastAccountLockoutEvent.ps1

.EXAMPLE
    .\Get-LastAccountLockoutEvent.ps1 -ExportPath "C:\Temp\RecentLockout.txt" -LogDirectory "C:\Temp"

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: Security Event Log Read Access, Administrator Elevation.
    Change Log   :
        1.0 - Initial sanitized production release.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0, HelpMessage = "Specify the target export file path.")]
    [ValidateNotNullOrEmpty()]
    [string]$ExportPath = "C:\Temp\lockout.txt",

    [Parameter(Mandatory = $false, HelpMessage = "Specify directory for execution log storage.")]
    [ValidateNotNullOrEmpty()]
    [string]$LogDirectory = "C:\Temp"
)

# --------------------------------------------------------------------------
# 1. PREREQUISITES & PRIVILEGE CHECKS
# --------------------------------------------------------------------------
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Error "This script requires administrative privileges to query the Security Event Log. Please run PowerShell as Administrator."
    exit 1
}

# --------------------------------------------------------------------------
# 2. LOGGING INITIALIZATION & HOUSEKEEPING
# --------------------------------------------------------------------------
$ScriptName = "Get_AccountLockoutEvent"
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
    Write-Log "Querying Security Event Log for the newest Account Lockout Event (Event ID 4740)..." "INFO"

    $FilterHashtable = @{
        LogName = 'Security'
        Id      = 4740
    }

    $LockoutEvent = Get-WinEvent -FilterHashtable $FilterHashtable -MaxEvents 1 -ErrorAction Stop

    if ($LockoutEvent) {
        Write-Log "Found lockout event logged at $($LockoutEvent.TimeCreated). Exporting details..." "INFO"

        $ExportDirectory = Split-Path -Path $ExportPath -Parent
        if (-not (Test-Path -Path $ExportDirectory)) {
            New-Item -Path $ExportDirectory -ItemType Directory -Force | Out-Null
        }

        # Remove existing target report file if present
        if (Test-Path -Path $ExportPath) {
            Remove-Item -Path $ExportPath -Force -ErrorAction SilentlyContinue
        }

        $LockoutEvent | Format-List * | Out-File -FilePath $ExportPath -Encoding utf8 -Force
        Write-Log "SUCCESS: Lockout event details exported to $ExportPath" "INFO"

        # Return object to pipeline
        $LockoutEvent
    }
}
catch [System.Exception] if ($_.Exception.Message -like "*No events were found*") {
    Write-Log "No Account Lockout Events (Event ID 4740) were found in the Security Event Log." "WARN"
}
catch {
    Write-Log "CRITICAL ERROR querying Security Event Log: $($_.Exception.Message)" "ERROR"
    exit 1
}