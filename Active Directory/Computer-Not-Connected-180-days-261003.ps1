#requires -Version 5.1

<#
.SYNOPSIS
    Disables inactive Active Directory computer accounts and updates their descriptions.

.DESCRIPTION
    Queries Active Directory for enabled computer accounts that have not logged on within a specified 
    threshold (default: 180 days). Exports the affected computer accounts to a CSV report, updates 
    their AD description with a timestamped disabled tag, and disables the computer accounts. 
    Includes native -WhatIf/-Confirm safety controls, execution logging in C:\Temp, and 7-day log cleanup.

.PARAMETER StaleDays
    The inactivity threshold in days. Computer accounts with a LastLogonTimestamp older than this value will be processed. Defaults to 180.

.PARAMETER ExportPath
    The target file path where the exported CSV report will be written. Defaults to 'C:\Temp\Computers_Inactive_180Days.csv'.

.PARAMETER LogDirectory
    The directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Disable-InactiveADComputers.ps1 -WhatIf

.EXAMPLE
    .\Disable-InactiveADComputers.ps1 -StaleDays 90 -ExportPath "C:\Temp\Computers_Inactive_90Days.csv" -Confirm:$false

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: RSAT Active Directory Tools module, Domain Administrator or Delegated Rights to modify computer objects.
    Change Log   :
        1.0 - Initial sanitized production release.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $false, Position = 0, HelpMessage = "Specify the inactivity threshold in days.")]
    [ValidateRange(1, 3650)]
    [int]$StaleDays = 180,

    [Parameter(Mandatory = $false, HelpMessage = "Specify the CSV export target path.")]
    [ValidateNotNullOrEmpty()]
    [string]$ExportPath = "C:\Temp\Computers_Inactive_180Days.csv",

    [Parameter(Mandatory = $false, HelpMessage = "Specify the directory for execution log storage.")]
    [ValidateNotNullOrEmpty()]
    [string]$LogDirectory = "C:\Temp"
)

# --------------------------------------------------------------------------
# 1. PREREQUISITES & PRIVILEGE CHECKS
# --------------------------------------------------------------------------
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Error "This script requires administrative privileges. Please run PowerShell as Administrator."
    exit 1
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
$ScriptName = "AD_DisableInactiveComputers"
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
    $CurrentDate = Get-Date
    $StaleDate   = $CurrentDate.AddDays(-$StaleDays)

    Write-Log "Searching Active Directory for ENABLED computer objects inactive for > $StaleDays days (Before $($StaleDate.ToString('yyyy-MM-dd')))..." "INFO"

    $StaleComputers = Get-ADComputer -Filter { (LastLogonTimestamp -lt $StaleDate) -and (Enabled -eq $true) } -Properties LastLogonTimestamp, Description, Enabled -ErrorAction Stop | 
        Where-Object { $_.LastLogonTimestamp -ne $null }

    if (-not $StaleComputers -or $StaleComputers.Count -eq 0) {
        Write-Log "No stale, ENABLED computer objects were found." "INFO"
        return
    }

    Write-Log "Found $($StaleComputers.Count) stale, ENABLED computer object(s)." "WARN"

    # Export Report
    $ExportDirectory = Split-Path -Path $ExportPath -Parent
    if (-not (Test-Path -Path $ExportDirectory)) {
        New-Item -Path $ExportDirectory -ItemType Directory -Force | Out-Null
    }

    $ReportData = $StaleComputers | Select-Object Name, DistinguishedName, @{Name='LastLogon';Expression={[DateTime]::FromFileTime($_.LastLogonTimestamp)}}, Description, Enabled
    $ReportData | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding utf8 -Force
    Write-Log "Exported affected computer list to: $ExportPath" "INFO"

    # Processing remediation actions
    foreach ($Computer in $StaleComputers) {
        $ComputerName   = $Computer.Name
        $LastLogon      = [DateTime]::FromFileTime($Computer.LastLogonTimestamp)
        $NewDescription = "DISABLED - $($CurrentDate.ToString('yyyy-MM-dd'))"

        Write-Log "Target Computer: $ComputerName (Last Logon: $LastLogon)" "INFO"

        if ($PSCmdlet.ShouldProcess($ComputerName, "Set Description to '$NewDescription' and Disable Computer Account")) {
            try {
                Set-ADComputer -Identity $Computer.DistinguishedName -Description $NewDescription -ErrorAction Stop
                Write-Log "Successfully updated description for '$ComputerName'." "INFO"

                Disable-ADAccount -Identity $Computer.DistinguishedName -ErrorAction Stop
                Write-Log "Successfully disabled computer account '$ComputerName'." "INFO"
            }
            catch {
                Write-Log "Failed to remediate computer '$ComputerName': $($_.Exception.Message)" "ERROR"
            }
        }
    }

    Write-Log "Script execution complete." "INFO"
}
catch {
    Write-Log "CRITICAL ERROR during Active Directory computer cleanup: $($_.Exception.Message)" "ERROR"
    exit 1
}