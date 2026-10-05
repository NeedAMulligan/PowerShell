#requires -Version 5.1

<#
.SYNOPSIS
    Calculates system boot time and uptime duration for the local or target computer.

.DESCRIPTION
    Queries the Win32_OperatingSystem CIM class to retrieve the last system boot-up time,
    calculates total system uptime elapsed against current system time, logs execution 
    activity to C:\Temp, and automatically cleans up log files older than 7 days.

.PARAMETER ComputerName
    The target computer name to query system uptime for. Defaults to the local computer name ($env:COMPUTERNAME).

.PARAMETER LogDirectory
    The local directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    Get-SystemUptime.ps1

.EXAMPLE
    Get-SystemUptime.ps1 -ComputerName "WORKSTATION01" -LogDirectory "C:\Temp"

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: Local or Remote CIM / WMI Access Rights.
    Change Log   :
        1.0 - Initial sanitized production release.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0, HelpMessage = "Specify the target computer name.")]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName = $env:COMPUTERNAME,

    [Parameter(Mandatory = $false, HelpMessage = "Specify directory for execution log storage.")]
    [ValidateNotNullOrEmpty()]
    [string]$LogDirectory = "C:\Temp"
)

# --------------------------------------------------------------------------
# 1. PREREQUISITES & PRIVILEGE CHECKS
# --------------------------------------------------------------------------
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Warning "Running in non-elevated context. Ensure proper privileges if querying remote endpoints."
}

# --------------------------------------------------------------------------
# 2. LOGGING INITIALIZATION & HOUSEKEEPING
# --------------------------------------------------------------------------
$ScriptName = "Get_SystemUptime"
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
    Write-Log "Querying system boot time on target computer: $ComputerName" "INFO"

    $CimParams = @{
        ClassName   = "Win32_OperatingSystem"
        ErrorAction = "Stop"
    }

    if ($ComputerName -ne $env:COMPUTERNAME) {
        $CimParams.Add("ComputerName", $ComputerName)
    }

    $OS = Get-CimInstance @CimParams
    $LastBootUpTime = $OS.LastBootUpTime

    if (-not $LastBootUpTime) {
        Write-Log "Failed to retrieve LastBootUpTime attribute from $ComputerName." "ERROR"
        exit 1
    }

    $UptimeSpan = (Get-Date) - $LastBootUpTime

    Write-Log "Target: $ComputerName | Last Boot Time: $LastBootUpTime | Total Uptime: $($UptimeSpan.Days) Days, $($UptimeSpan.Hours) Hours, $($UptimeSpan.Minutes) Minutes" "INFO"

    # Pipeline output
    [PSCustomObject]@{
        ComputerName   = $ComputerName
        LastBootUpTime = $LastBootUpTime
        UptimeDays     = $UptimeSpan.Days
        UptimeHours    = $UptimeSpan.Hours
        UptimeMinutes  = $UptimeSpan.Minutes
        UptimeSeconds  = $UptimeSpan.Seconds
        UptimeFormatted= "$($UptimeSpan.Days)d $($UptimeSpan.Hours)h $($UptimeSpan.Minutes)m $($UptimeSpan.Seconds)s"
    }
}
catch {
    Write-Log "CRITICAL ERROR querying system uptime on '$ComputerName': $($_.Exception.Message)" "ERROR"
    exit 1
}