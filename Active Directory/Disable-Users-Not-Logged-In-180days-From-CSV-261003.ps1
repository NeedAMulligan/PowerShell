#requires -Version 5.1

<#
.SYNOPSIS
    Disables Active Directory user accounts specified in a CSV file, updates their descriptions, and moves them to a target OU.

.DESCRIPTION
    Reads a list of user accounts from an imported CSV file containing SamAccountName values. 
    For each valid Active Directory user, it updates the user's description with a timestamped disabled tag, 
    disables the user account, and moves the object into a designated target Organizational Unit (OU). 
    Includes native -WhatIf/-Confirm safety controls, execution logging in C:\Temp, and 7-day log cleanup.

.PARAMETER CsvFilePath
    The local or network path to the input CSV file containing user account details. Defaults to 'C:\Temp\users-180-days.csv'.

.PARAMETER DisabledUsersOU
    The Distinguished Name (DN) of the target Organizational Unit where disabled users will be moved.

.PARAMETER LogDirectory
    The directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Disable-ADUsersFromCSV.ps1 -DisabledUsersOU "OU=Disabled Users,DC=contoso,DC=com" -WhatIf

.EXAMPLE
    .\Disable-ADUsersFromCSV.ps1 -CsvFilePath "C:\Temp\stale_users.csv" -DisabledUsersOU "OU=Disabled,DC=contoso,DC=com" -Confirm:$false

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: RSAT Active Directory Tools module, Domain Administrator or Delegated Rights to modify and move user objects.
    Change Log   :
        1.0 - Initial sanitized production release.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $false, Position = 0, HelpMessage = "Specify the path to the input CSV file.")]
    [ValidateNotNullOrEmpty()]
    [string]$CsvFilePath = "C:\Temp\users-180-days.csv",

    [Parameter(Mandatory = $true, Position = 1, HelpMessage = "Specify the target Distinguished Name (DN) for the Disabled Users OU.")]
    [ValidateNotNullOrEmpty()]
    [string]$DisabledUsersOU,

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
$ScriptName = "AD_DisableUsersFromCSV"
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
    if (-not (Test-Path -Path $CsvFilePath)) {
        Write-Log "Input CSV file not found at path: $CsvFilePath" "ERROR"
        exit 1
    }

    # Verify Target OU existence
    try {
        [void](Get-ADOrganizationalUnit -Identity $DisabledUsersOU -ErrorAction Stop)
    }
    catch {
        Write-Log "Target Disabled Users OU '$DisabledUsersOU' was not found or is invalid: $($_.Exception.Message)" "ERROR"
        exit 1
    }

    $DisableDate = Get-Date -Format "yyyy-MM-dd"
    Write-Log "Importing user list from CSV: $CsvFilePath" "INFO"

    $UsersToDisable = Import-Csv -Path $CsvFilePath -ErrorAction Stop

    if (-not $UsersToDisable -or $UsersToDisable.Count -eq 0) {
        Write-Log "The CSV file is empty or contains no records." "WARN"
        return
    }

    Write-Log "Processing $($UsersToDisable.Count) user record(s) for remediation..." "INFO"

    foreach ($UserRecord in $UsersToDisable) {
        $SamAccountName = $UserRecord.SamAccountName

        if ([string]::IsNullOrWhiteSpace($SamAccountName)) {
            Write-Log "Skipping record with missing or empty SamAccountName." "WARN"
            continue
        }

        Write-Log "Processing target user: $SamAccountName" "INFO"

        # Locate User in Active Directory
        try {
            $ADUser = Get-ADUser -Identity $SamAccountName -ErrorAction Stop
        }
        catch {
            Write-Log "User '$SamAccountName' not found in Active Directory. Skipping." "WARN"
            continue
        }

        $NewDescription = "Disabled with date: $DisableDate"

        if ($PSCmdlet.ShouldProcess($SamAccountName, "Disable Account, Update Description, and Move to '$DisabledUsersOU'")) {
            # Step 1: Update Description
            try {
                Set-ADUser -Identity $ADUser -Description $NewDescription -ErrorAction Stop
                Write-Log "  - Description updated to '$NewDescription'." "INFO"
            }
            catch {
                Write-Log "  - Failed to update description for '$SamAccountName': $($_.Exception.Message)" "ERROR"
            }

            # Step 2: Disable Account
            try {
                Disable-ADAccount -Identity $ADUser -ErrorAction Stop
                Write-Log "  - Account successfully disabled." "INFO"
            }
            catch {
                Write-Log "  - Failed to disable account for '$SamAccountName': $($_.Exception.Message)" "ERROR"
            }

            # Step 3: Move to Target OU
            try {
                Move-ADObject -Identity $ADUser -TargetPath $DisabledUsersOU -ErrorAction Stop
                Write-Log "  - User successfully moved to '$DisabledUsersOU'." "INFO"
            }
            catch {
                Write-Log "  - Failed to move user '$SamAccountName' to '$DisabledUsersOU': $($_.Exception.Message)" "ERROR"
            }
        }
    }

    Write-Log "User remediation process completed." "INFO"
}
catch {
    Write-Log "CRITICAL ERROR during user processing: $($_.Exception.Message)" "ERROR"
    exit 1
}