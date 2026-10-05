#requires -Version 5.1

<#
.SYNOPSIS
    Backs up all Group Policy Objects (GPOs) in the domain to a timestamped target directory.

.DESCRIPTION
    Queries Active Directory for all existing Group Policy Objects and exports full backups 
    to a timestamped folder under the configured backup root directory. Logs execution activity 
    to C:\Temp, supports native -WhatIf/-Confirm safety controls, and automatically performs 
    a 7-day log cleanup maintenance routine prior to execution.

.PARAMETER BackupRootDirectory
    The root directory path where timestamped GPO backup folders will be created. Defaults to 'C:\GPO_Backup'.

.PARAMETER Domain
    Target Active Directory Domain or Domain Controller FQDN. Defaults to the current domain if omitted.

.PARAMETER LogDirectory
    The local directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Backup-GroupPolicyObjects.ps1

.EXAMPLE
    .\Backup-GroupPolicyObjects.ps1 -BackupRootDirectory "D:\Backups\GPO" -WhatIf

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: RSAT Group Policy Management Tools module, Domain Administrator or Delegated GPO Backup Rights.
    Change Log   :
        1.0 - Initial sanitized production release.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false, Position = 0, HelpMessage = "Specify the root directory for GPO backups.")]
    [ValidateNotNullOrEmpty()]
    [string]$BackupRootDirectory = "C:\GPO_Backup",

    [Parameter(Mandatory = $false, HelpMessage = "Specify target domain or Domain Controller FQDN.")]
    [string]$Domain,

    [Parameter(Mandatory = $false, HelpMessage = "Specify directory for execution log storage.")]
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

$RequiredModule = "GroupPolicy"

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
$ScriptName = "Backup_GroupPolicyObjects"
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
    $TodayFolder = Get-Date -Format "yyyyMMdd"
    $TargetBackupPath = Join-Path -Path $BackupRootDirectory -ChildPath $TodayFolder

    Write-Log "Initializing Group Policy Object backup routine..." "INFO"
    Write-Log "Target Backup Destination Directory: $TargetBackupPath" "INFO"

    if (-not (Test-Path -Path $TargetBackupPath)) {
        New-Item -Path $TargetBackupPath -ItemType Directory -Force | Out-Null
    }

    $GpoQueryParams = @{
        All         = $true
        ErrorAction = "Stop"
    }

    if ($Domain) {
        $GpoQueryParams.Add("Domain", $Domain)
        Write-Log "Targeting Domain: $Domain" "INFO"
    }

    $GPOs = Get-GPO @GpoQueryParams

    if (-not $GPOs -or $GPOs.Count -eq 0) {
        Write-Log "No Group Policy Objects were found in the target domain." "WARN"
        return
    }

    Write-Log "Discovered $($GPOs.Count) Group Policy Object(s). Starting backups..." "INFO"

    $SuccessCount = 0
    $FailureCount = 0

    foreach ($GPO in $GPOs) {
        $GPOName = $GPO.DisplayName
        $GPOId   = $GPO.Id

        if ($PSCmdlet.ShouldProcess($GPOName, "Backup GPO to '$TargetBackupPath'")) {
            try {
                Write-Log "Backing up GPO: '$GPOName' ($GPOId)..." "INFO"

                $BackupParams = @{
                    Guid        = $GPOId
                    Path        = $TargetBackupPath
                    ErrorAction = "Stop"
                }

                if ($Domain) {
                    $BackupParams.Add("Domain", $Domain)
                }

                $BackupResult = Backup-GPO @BackupParams
                Write-Log "SUCCESS: Backed up '$GPOName' (Backup ID: $($BackupResult.Id))." "INFO"
                $SuccessCount++
            }
            catch {
                Write-Log "ERROR: Failed to back up GPO '$GPOName': $($_.Exception.Message)" "ERROR"
                $FailureCount++
            }
        }
    }

    Write-Log "GPO Backup Process Complete. Successful: $SuccessCount | Failed: $FailureCount" "INFO"
}
catch {
    Write-Log "CRITICAL ERROR during GPO backup execution: $($_.Exception.Message)" "ERROR"
    exit 1
}