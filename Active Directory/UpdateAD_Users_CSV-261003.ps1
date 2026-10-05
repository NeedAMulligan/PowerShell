#requires -Version 5.1

<#
.SYNOPSIS
    Imports user metadata from a CSV file and updates corresponding Active Directory user attributes.

.DESCRIPTION
    Reads a CSV export containing user metadata (such as DisplayName, Email, Address, City, PostalCode, Title, 
    Company, Phone, State, and Department) and bulk-updates Active Directory user account properties. 
    Includes native -WhatIf/-Confirm safety controls, execution logging in C:\Temp, and automated 7-day log maintenance cleanup.

.PARAMETER CsvPath
    The file path of the CSV export containing user attribute data to import.

.PARAMETER LogDirectory
    The local directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Import-ADUserMetadata.ps1 -CsvPath "C:\Temp\AllADUsers.csv" -WhatIf

.EXAMPLE
    .\Import-ADUserMetadata.ps1 -CsvPath "D:\Imports\UsersUpdate.csv" -Confirm:$false

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: RSAT Active Directory Tools module, Domain Administrator or Delegated Rights to modify user attributes.
    Change Log   :
        1.0 - Initial sanitized production release.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Specify path to user metadata CSV file.")]
    [ValidateNotNullOrEmpty()]
    [string]$CsvPath,

    [Parameter(Mandatory = $false, HelpMessage = "Specify directory for execution log storage.")]
    [ValidateNotNullOrEmpty()]
    [string]$LogDirectory = "C:\Temp"
)

# --------------------------------------------------------------------------
# 1. PREREQUISITES & PRIVILEGE CHECKS
# --------------------------------------------------------------------------
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Error "This script requires administrative privileges to modify Active Directory attributes. Please run PowerShell as Administrator."
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
$ScriptName = "AD_ImportUserMetadata"
$DateStamp  = Get-Date -Format "yyyyMMdd_HHmmss"

if (-not (Test-Path -Path $LogDirectory)) {
    New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
}

# Log rotation: Remove log files older than 7 days from `C:\Temp`
Get-ChildItem -Path $LogDirectory -Filter "*.log" -File -ErrorAction SilentlyContinue | 
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } | 
    Remove-Item -Force -ErrorAction SilentlyContinue

$LogFile = Join-Path -Path$LogDirectory -ChildPath "$($ScriptName)_$($DateStamp).log"

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )
    $LogEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] -$Message"
    $LogEntry \vert{} Out-File -FilePath$LogFile -Append -Encoding utf8
    
    $Color = switch ($Level) {
        "ERROR" { "Red" }
        "WARN"  { "Yellow" }
        Default { "Cyan" }
    }
    Write-Host $LogEntry -ForegroundColor$Color
}

# --------------------------------------------------------------------------
# 3. SCRIPT EXECUTION
# --------------------------------------------------------------------------
try {
    Write-Log "Initializing Active Directory User Metadata import routine..."
    Write-Log "Target CSV Import Path: $CsvPath"

    if (-not (Test-Path -Path $CsvPath)) {
        Write-Log "CRITICAL ERROR: Specified CSV file path '$CsvPath' does not exist." "ERROR"
        exit 1
    }

    $CsvData = Import-Csv -Path$CsvPath -ErrorAction Stop
    if (-not $CsvData -or$CsvData.Count -eq 0) {
        Write-Log "WARNING: CSV file is empty or contains no records." "WARN"
        return
    }

    Write-Log "Loaded $($CsvData.Count) record(s) from CSV. Processing Active Directory updates..."

    $SuccessCount = 0$FailureCount = 0

    foreach ($Row in$CsvData) {
        $UserName =$Row.Name
        if ([string]::IsNullOrWhiteSpace($UserName)) {
            continue
        }

        if ($PSCmdlet.ShouldProcess($UserName, "Update Active Directory User Attributes")) {
            try {
                $ADUser = Get-ADUser -Filter "DisplayName -eq '$UserName'" -ErrorAction Stop

                if ($ADUser) {
                    Set-ADUser -Identity $ADUser.DistinguishedName `
                        -EmailAddress   $Row.Email `
                        -StreetAddress  $Row.address `
                        -City           $Row.City `
                        -PostalCode     $Row.zip `
                        -Title          $Row."Job Title" `
                        -Company        $Row.Company `
                        -OfficePhone    $Row.Phone `
                        -State          $Row.State `
                        -Department     $Row.Department `
                        -ErrorAction Stop

                    Write-Log "SUCCESS: Updated attributes for user '$UserName'."
                    $SuccessCount++
                }
                else {
                    Write-Log "WARNING: User matching DisplayName '$UserName' was not found in Active Directory." "WARN"
                    $FailureCount++
                }
            }
            catch {
                Write-Log "ERROR updating user '$UserName': $($_.Exception.Message)" "ERROR"
                $FailureCount++
            }
        }
    }

    Write-Log "Metadata import complete. Successful: $SuccessCount \vert{} Failed/Skipped:$FailureCount"
}
catch {
    Write-Log "CRITICAL ERROR during metadata import execution: $($_.Exception.Message)" "ERROR"
    exit 1
}