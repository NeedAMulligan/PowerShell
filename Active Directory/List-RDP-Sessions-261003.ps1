#requires -Version 5.1

<#
.SYNOPSIS
    Audits Remote Desktop (RDP) authentication attempts by querying Event ID 1149 from Terminal Services Operational logs.

.DESCRIPTION
    Queries the 'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational' Security Event Log 
    for Event ID 1149 (User Authentication Succeeded). Extracts target user, domain, and client IP address details 
    from the event XML data and outputs structured objects directly to the pipeline. Writes execution logs 
    to C:\Temp and automatically maintains a 7-day log cleanup rotation.

.PARAMETER MaxEvents
    The maximum number of Event ID 1149 records to retrieve. Defaults to 1000.

.PARAMETER ExportPath
    Optional CSV file path to export the RDP authentication audit results.

.PARAMETER LogDirectory
    The local directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Get-RDPAuthenticationEvents.ps1

.EXAMPLE
    .\Get-RDPAuthenticationEvents.ps1 -MaxEvents 500 -ExportPath "C:\Temp\RDP_Auth_Audit.csv"

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: Local Administrative Privileges (to access Terminal Services Operational logs).
    Change Log   :
        1.0 - Initial sanitized production release.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0, HelpMessage = "Maximum number of RDP authentication events to retrieve.")]
    [ValidateRange(1, 100000)]
    [int]$MaxEvents = 1000,

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
    Write-Error "This script requires administrative privileges to query TerminalServices Event Logs. Please run PowerShell as Administrator."
    exit 1
}

# --------------------------------------------------------------------------
# 2. LOGGING INITIALIZATION & HOUSEKEEPING
# --------------------------------------------------------------------------
$ScriptName = "Audit_RDPAuthenticationEvents"
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
    $TargetLog = 'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational'
    $FilterXPath = '<QueryList><Query Id="0"><Select>*[System[EventID=1149]]</Select></Query></QueryList>'

    Write-Log "Querying RDP Authentication events (ID 1149) from log: $TargetLog (Max: $MaxEvents)..." "INFO"

    $RDPAuthEvents = Get-WinEvent -LogName $TargetLog -FilterXPath $FilterXPath -MaxEvents $MaxEvents -ErrorAction SilentlyContinue

    if (-not $RDPAuthEvents -or $RDPAuthEvents.Count -eq 0) {
        Write-Log "No RDP authentication events (Event ID 1149) were found in the log." "WARN"
        return
    }

    Write-Log "Retrieved $($RDPAuthEvents.Count) RDP authentication event(s). Processing XML payload..." "INFO"

    $Results = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($Event in $RDPAuthEvents) {
        try {
            [xml]$XmlEvent = $Event.ToXml()

            $TimeCreatedString = $XmlEvent.Event.System.TimeCreated.SystemTime
            $TimeCreated = if ($TimeCreatedString) { [Get-Date $TimeCreatedString] } else { $Event.TimeCreated }

            $UserData = $XmlEvent.Event.UserData.EventXML

            $User   = if ($UserData.Param1) { $UserData.Param1 } else { "Unknown" }
            $Domain = if ($UserData.Param2) { $UserData.Param2 } else { "Unknown" }
            $Client = if ($UserData.Param3) { $UserData.Param3 } else { "Unknown" }

            $Results.Add([PSCustomObject]@{
                TimeCreated = $TimeCreated
                User        = $User
                Domain      = $Domain
                Client      = $Client
            })
        }
        catch {
            Write-Log "Warning: Failed to parse XML for Event ID 1149 record generated at $($Event.TimeCreated): $($_.Exception.Message)" "WARN"
        }
    }

    Write-Log "Successfully parsed $($Results.Count) RDP authentication event record(s)." "INFO"

    if (-not [string]::IsNullOrWhiteSpace($ExportPath)) {
        $ExportDir = Split-Path -Path $ExportPath -Parent
        if ($ExportDir -and (-not (Test-Path -Path $ExportDir))) {
            New-Item -Path $ExportDir -ItemType Directory -Force | Out-Null
        }
        $Results | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding utf8
        Write-Log "SUCCESS: Exported audit results to: $ExportPath" "INFO"
    }

    # Pipeline Output
    $Results
}
catch {
    Write-Log "CRITICAL ERROR during RDP authentication event audit: $($_.Exception.Message)" "ERROR"
    exit 1
}