#requires -Version 5.1

<#
.SYNOPSIS
    Queries Active Directory for computer accounts that have been inactive for a specified number of days and exports the results to CSV.

.DESCRIPTION
    Identifies inactive computer objects in Active Directory based on the lastLogonTimeStamp attribute. 
    Converts raw FileTime values into human-readable DateTime objects, exports the report to CSV, 
    writes execution logs to C:\Temp, and automatically performs 7-day log cleanup maintenance.

.PARAMETER DaysInactive
    The inactivity threshold in days. Accounts with lastLogonTimeStamp older than this value will be returned. Defaults to 180 days.

.PARAMETER SearchBase
    The Distinguished Name (DN) of the Organizational Unit (OU) or container to query. If omitted, searches across the entire domain.

.PARAMETER ExportPath
    The file path where the exported CSV report will be saved. Defaults to 'C:\Temp\AD_InactiveComputers_<yyyyMMdd_HHmmss>.csv'.

.PARAMETER LogDirectory
    The local directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Get-ADInactiveComputers.ps1

.EXAMPLE
    .\Get-ADInactiveComputers.ps1 -DaysInactive 90 -SearchBase "OU=Workstations,DC=contoso,DC=com"

.EXAMPLE
    .\Get-ADInactiveComputers.ps1 -DaysInactive 365 -ExportPath "C:\Temp\OldComputersReport.csv"

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: RSAT Active Directory Tools module, Domain User privileges.
    Change Log   :
        1.0 - Initial sanitized production release.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0, HelpMessage = "Threshold number of inactive days.")]
    [ValidateRange(1, 3650)]
    [int]$DaysInactive = 180,

    [Parameter(Mandatory = $false, Position = 1, HelpMessage = "Specify Distinguished Name (DN) search base context.")]
    [string]$SearchBase,

    [Parameter(Mandatory = $false, HelpMessage = "Specify target CSV output file path.")]
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
$ScriptName = "AD_GetInactiveComputers"
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
        $ExportPath = Join-Path -Path $LogDirectory -ChildPath "AD_InactiveComputers_${DateStamp}.csv"
    }

    $CutoffDate = (Get-Date).AddDays(-$DaysInactive)
    $CutoffFileTime = $CutoffDate.ToFileTime()

    Write-Log "Querying Active Directory for computer accounts inactive since $CutoffDate ($DaysInactive days threshold)..." "INFO"

    $QueryParams = @{
        Filter      = "lastlogontimestamp -lt $CutoffFileTime"
        Properties  = @('Name', 'OperatingSystem', 'lastlogontimestamp')
        ErrorAction = "Stop"
    }

    if ([string]::IsNullOrWhiteSpace($SearchBase)) {
        Write-Log "Searching across domain root..." "INFO"
    }
    else {
        Write-Log "Searching within Search Base context: $SearchBase" "INFO"
        $QueryParams.Add("SearchBase", $SearchBase)
    }

    $RawComputers = Get-ADComputer @QueryParams

    if (-not $RawComputers -or $RawComputers.Count -eq 0) {
        Write-Log "No inactive computer accounts were found matching the criteria." "WARN"
        return
    }

    Write-Log "Discovered $($RawComputers.Count) inactive computer account(s). Formatting report..." "INFO"

    $Results = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($Comp in $RawComputers) {
        $LastLogonDate = if ($Comp.lastlogontimestamp) {
            [DateTime]::FromFileTime($Comp.lastlogontimestamp)
        }
        else {
            $null
        }

        $Results.Add([PSCustomObject]@{
            Name                = $Comp.Name
            OperatingSystem     = $Comp.OperatingSystem
            lastlogontimestamp  = $LastLogonDate
        })
    }

    $ExportDir = Split-Path -Path $ExportPath -Parent
    if ($ExportDir -and (-not (Test-Path -Path $ExportDir))) {
        New-Item -Path $ExportDir -ItemType Directory -Force | Out-Null
    }

    $Results | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding utf8
    Write-Log "SUCCESS: Exported $($Results.Count) inactive computer record(s) to: $ExportPath" "INFO"

    # Pipeline output
    $Results
}
catch {
    Write-Log "CRITICAL ERROR during inactive computer query execution: $($_.Exception.Message)" "ERROR"
    exit 1
}