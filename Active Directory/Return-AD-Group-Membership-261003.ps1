#requires -Version 5.1

<#
.SYNOPSIS
    Generates a matrix CSV report mapping Active Directory groups to their associated member DNs across columns.

.DESCRIPTION
    Queries all Active Directory groups and their member attributes, calculates the maximum membership depth, 
    and constructs a tabular matrix where each group forms a column header populated with member Distinguished Names. 
    Writes execution logs to C:\Temp\ and performs automated 7-day log maintenance cleanup.

.PARAMETER SearchBase
    The Distinguished Name (DN) of the Organizational Unit (OU) or container to query groups from. 
    If omitted, queries groups across the entire domain.

.PARAMETER ExportPath
    The target CSV file path for the matrix report. Defaults to 'C:\Temp\AD_GroupMemberMatrix_<yyyyMMdd_HHmmss>.csv'.

.PARAMETER LogDirectory
    The local directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Export-ADGroupMemberMatrix.ps1

.EXAMPLE
    .\Export-ADGroupMemberMatrix.ps1 -SearchBase "OU=Groups,DC=contoso,DC=com" -ExportPath "C:\Temp\GroupMatrix.csv"

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: RSAT Active Directory Tools module, Domain User privileges.
    Change Log   :
        1.0 - Initial sanitized production release (Refactored matrix assembly logic).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0, HelpMessage = "Specify Distinguished Name (DN) search base context.")]
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
$ScriptName = "AD_ExportGroupMemberMatrix"
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
    if ([string]::IsNullOrWhiteSpace($ExportPath)) {
        $ExportPath = Join-Path -Path $LogDirectory -ChildPath "AD_GroupMemberMatrix_${DateStamp}.csv"
    }

    Write-Log "Initializing Active Directory Group Member Matrix export..." "INFO"

    $QueryParams = @{
        Filter      = "*"
        Properties  = @("members")
        ErrorAction = "Stop"
    }

    if ([string]::IsNullOrWhiteSpace($SearchBase)) {
        Write-Log "Searching across domain root..." "INFO"
    }
    else {
        Write-Log "Searching within Search Base context: $SearchBase" "INFO"
        $QueryParams.Add("SearchBase", $SearchBase)
    }

    $AllGroups = Get-ADGroup @QueryParams

    if (-not $AllGroups -or $AllGroups.Count -eq 0) {
        Write-Log "No Active Directory groups were found in specified scope." "WARN"
        return
    }

    Write-Log "Retrieved $($AllGroups.Count) group(s). Pre-caching memberships and calculating depth..." "INFO"

    $GroupMap = [ordered]@{}
    $MaxRows = 0

    foreach ($Group in $AllGroups) {
        $Members = @($Group.members)
        $GroupMap[$Group.Name] = $Members
        if ($Members.Count -gt $MaxRows) {
            $MaxRows = $Members.Count
        }
    }

    Write-Log "Maximum membership depth across groups: $MaxRows row(s). Constructing matrix objects..." "INFO"

    $Matrix = [System.Collections.Generic.List[PSCustomObject]]::new()

    for ($RowIndex = 0; $RowIndex -lt $MaxRows; $RowIndex++) {
        $RowProps = [ordered]@{}
        foreach ($GroupName in $GroupMap.Keys) {
            $MemberList = $GroupMap[$GroupName]
            if ($RowIndex -lt $MemberList.Count) {
                $RowProps[$GroupName] = $MemberList[$RowIndex]
            }
            else {
                $RowProps[$GroupName] = ""
            }
        }
        $Matrix.Add([PSCustomObject]$RowProps)
    }

    $ExportDir = Split-Path -Path $ExportPath -Parent
    if ($ExportDir -and (-not (Test-Path -Path $ExportDir))) {
        New-Item -Path $ExportDir -ItemType Directory -Force | Out-Null
    }

    $Matrix | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding utf8
    Write-Log "SUCCESS: Exported Group Membership Matrix ($($AllGroups.Count) columns, $MaxRows rows) to: $ExportPath" "INFO"

    # Pipeline output
    $Matrix
}
catch {
    Write-Log "CRITICAL ERROR during group matrix report execution: $($_.Exception.Message)" "ERROR"
    exit 1
}