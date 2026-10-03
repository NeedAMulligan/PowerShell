#requires -Version 5.1

<#
.SYNOPSIS
    Exports Active Directory user account details to a CSV report.

.DESCRIPTION
    Queries Active Directory user accounts within a specified domain or search base, converts property 
    values into human-readable report headers, filters out migrated accounts (where the info/Notes 
    field contains 'Migrated'), and exports the data to a CSV file. Includes standard execution 
    logging in C:\Temp and automatic 7-day log cleanup.

.PARAMETER Domain
    The target Active Directory domain or Domain Controller FQDN. Defaults to the current domain if omitted.

.PARAMETER SearchBase
    The Distinguished Name (DN) of the Organizational Unit (OU) or container to query.
    If omitted, queries user accounts across the entire domain.

.PARAMETER Credential
    Optional PSCredential object used to authenticate against Active Directory if running under an alternate context.

.PARAMETER ExportPath
    The target file path where the exported CSV report will be written. Defaults to 'C:\Temp\ALLADUsers_<yyyyMMddHHmm>.csv'.

.PARAMETER LogDirectory
    The local directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Export-ADUserReport.ps1

.EXAMPLE
    .\Export-ADUserReport.ps1 -SearchBase "OU=Employees,DC=contoso,DC=com" -ExportPath "C:\Temp\UserReport.csv"

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: RSAT Active Directory Tools module, Domain User or Administrative privileges.
    Change Log   :
        1.0 - Initial sanitized production release.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0, HelpMessage = "Specify target Active Directory Domain or Server FQDN.")]
    [string]$Domain,

    [Parameter(Mandatory = $false, Position = 1, HelpMessage = "Specify Distinguished Name (DN) search base context.")]
    [string]$SearchBase,

    [Parameter(Mandatory = $false, HelpMessage = "Specify alternate credentials for Active Directory connection.")]
    [PSCredential]$Credential,

    [Parameter(Mandatory = $false, HelpMessage = "Specify target CSV output file path.")]
    [ValidateNotNullOrEmpty()]
    [string]$ExportPath = "C:\Temp\ALLADUsers_$(Get-Date -Format 'yyyyMMddHHmm').csv",

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
$ScriptName = "AD_UserExport"
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
    $QueryParams = @{
        Filter      = "*"
        Properties  = @(
            'GivenName', 'Surname', 'DisplayName', 'sAMAccountName', 'StreetAddress',
            'City', 'st', 'PostalCode', 'Country', 'Title', 'Company', 'Description',
            'Department', 'OfficeName', 'telephoneNumber', 'Mail', 'Manager', 'Enabled',
            'lastlogondate', 'info'
        )
        ErrorAction = "Stop"
    }

    if ($Domain) { $QueryParams.Add("Server", $Domain) }
    if ($Credential) { $QueryParams.Add("Credential", $Credential) }

    if ([string]::IsNullOrWhiteSpace($SearchBase)) {
        Write-Log "Searching Active Directory user accounts across the entire domain..." "INFO"
    }
    else {
        Write-Log "Searching Active Directory user accounts in Search Base: $SearchBase" "INFO"
        $QueryParams.Add("SearchBase", $SearchBase)
    }

    $RawUsers = Get-ADUser @QueryParams

    if (-not $RawUsers -or $RawUsers.Count -eq 0) {
        Write-Log "No Active Directory user accounts found in specified scope." "WARN"
        return
    }

    Write-Log "Retrieved $($RawUsers.Count) user account(s). Filtering migrated accounts and formatting report..." "INFO"

    # Filter out users with info field set to 'Migrated'
    $FilteredUsers = $RawUsers | Where-Object { $_.info -ne 'Migrated' }
    Write-Log "Processing $($FilteredUsers.Count) active/non-migrated user record(s)..." "INFO"

    $Results = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($User in $FilteredUsers) {
        $ManagerDisplayName = ""
        if ($User.Manager) {
            try {
                $ManagerObject = Get-ADUser -Identity $User.Manager -Properties DisplayName -ErrorAction SilentlyContinue
                if ($ManagerObject) { $ManagerDisplayName = $ManagerObject.DisplayName }
            }
            catch {
                Write-Log "Could not resolve Manager identity for user $($User.sAMAccountName)" "WARN"
            }
        }

        $CountryName = if ($User.Country -eq 'GB') { 'United Kingdom' } else { $User.Country }
        $AccountStatus = if ($User.Enabled -eq $true) { 'Enabled' } else { 'Disabled' }

        $Results.Add([PSCustomObject]@{
            "First Name"     = $User.GivenName
            "Last Name"      = $User.Surname
            "Display Name"   = $User.DisplayName
            "Logon Name"     = $User.sAMAccountName
            "Full address"   = $User.StreetAddress
            "City"           = $User.City
            "State"          = $User.st
            "Post Code"      = $User.PostalCode
            "Country/Region" = $CountryName
            "Job Title"      = $User.Title
            "Company"        = $User.Company
            "Directorate"    = $User.Description
            "Department"     = $User.Department
            "Office"         = $User.OfficeName
            "Phone"          = $User.telephoneNumber
            "Email"          = $User.Mail
            "Manager"        = $ManagerDisplayName
            "Account Status" = $AccountStatus
            "Last LogOn Date"= $User.lastlogondate
        })
    }

    $ExportDirectory = Split-Path -Path $ExportPath -Parent
    if (-not (Test-Path -Path $ExportDirectory)) {
        New-Item -Path $ExportDirectory -ItemType Directory -Force | Out-Null
    }

    $Results | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding utf8
    Write-Log "SUCCESS! Exported $($Results.Count) user record(s) to: $ExportPath" "INFO"
}
catch {
    Write-Log "CRITICAL ERROR during Active Directory export execution: $($_.Exception.Message)" "ERROR"
    exit 1
}