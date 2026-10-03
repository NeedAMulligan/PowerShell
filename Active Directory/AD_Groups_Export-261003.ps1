#requires -Version 5.1

<#
.SYNOPSIS
    Exports Active Directory groups and their member lists to a CSV report.

.DESCRIPTION
    Queries all Active Directory groups in the domain, collects group metadata (Name, Category, Scope), 
    and concatenates group member names into a comma-separated list. Exports the compiled data to a CSV 
    report. Includes execution logging in C:\Temp and automated cleanup of log files older than 7 days.

.PARAMETER ExportPath
    The target file path where the exported CSV report will be written. Defaults to 'C:\Temp\AD_Groups_Export_<yyyyMM>.csv'.

.PARAMETER LogDirectory
    The directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Export-ADGroupMembers.ps1

.EXAMPLE
    .\Export-ADGroupMembers.ps1 -ExportPath "C:\Temp\DomainGroupsReport.csv" -LogDirectory "C:\Temp"

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: RSAT Active Directory Tools module, Domain User or Administrative privileges.
    Change Log   :
        1.0 - Initial sanitized production release.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0, HelpMessage = "Specify the target CSV output file path.")]
    [ValidateNotNullOrEmpty()]
    [string]$ExportPath = "C:\Temp\AD_Groups_Export_$(Get-Date -Format 'yyyyMM').csv",

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
$ScriptName = "AD_GroupExport"
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
    Write-Log "Querying Active Directory for all domain groups..." "INFO"

    $ADGroups = Get-ADGroup -Filter * -ErrorAction Stop
    $TotalGroups = $ADGroups.Count

    if (-not $ADGroups) {
        Write-Log "No Active Directory groups found in target domain." "WARN"
        return
    }

    Write-Log "Retrieved $TotalGroups Active Directory group(s). Processing memberships..." "INFO"

    $CSVOutput = [System.Collections.Generic.List[PSCustomObject]]::new()
    $Counter = 0

    foreach ($ADGroup in $ADGroups) {
        $Counter++
        $PercentComplete = [math]::Round(($Counter / $TotalGroups) * 100)
        Write-Progress -Activity "Exporting Active Directory Groups" -Status "Processing group $Counter of $TotalGroups ($PercentComplete%)" -PercentComplete $PercentComplete

        $MembersString = ""
        try {
            $GroupMembers = Get-ADGroupMember -Identity $ADGroup.DistinguishedName -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
            if ($GroupMembers) {
                $MembersString = $GroupMembers -join ","
            }
        }
        catch {
            Write-Log "Failed to retrieve members for group '$($ADGroup.Name)': $($_.Exception.Message)" "WARN"
        }

        $CSVOutput.Add([PSCustomObject]@{
            "Name"     = $ADGroup.Name
            "Category" = $ADGroup.GroupCategory
            "Scope"    = $ADGroup.GroupScope
            "Members"  = $MembersString
        })
    }

    Write-Progress -Activity "Exporting Active Directory Groups" -Completed

    $ExportDirectory = Split-Path -Path $ExportPath -Parent
    if (-not (Test-Path -Path $ExportDirectory)) {
        New-Item -Path $ExportDirectory -ItemType Directory -Force | Out-Null
    }

    $CSVOutput | Sort-Object -Property Name | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding utf8
    Write-Log "SUCCESS! Exported $($CSVOutput.Count) group record(s) to: $ExportPath" "INFO"
}
catch {
    Write-Log "CRITICAL ERROR during Active Directory group export: $($_.Exception.Message)" "ERROR"
    exit 1
}