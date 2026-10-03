#requires -Version 5.1

<#
.SYNOPSIS
    Exports Microsoft Entra ID (Azure AD) user account metadata and manager relationships to a CSV report.

.DESCRIPTION
    Connects to Microsoft Graph SDK, queries user account attributes (enabled/disabled/all), optionally 
    resolves user manager display names, and exports the structured data to a CSV file.
    Logs execution activity to C:\Temp\ and automatically cleans up log files older than 7 days.

.PARAMETER GetManager
    Switch parameter specifying whether to query and resolve each user's manager. Defaults to $true.

.PARAMETER AccountStatus
    Filters returned users by account status. Accepted values: 'Enabled', 'Disabled', 'All'. Defaults to 'Enabled'.

.PARAMETER ExportPath
    The target file path where the exported CSV report will be written. Defaults to 'C:\Temp\ADUsers_<MMM-dd-yyyy>.csv'.

.PARAMETER LogDirectory
    The local directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Export-EntraIDUsers.ps1

.EXAMPLE
    .\Export-EntraIDUsers.ps1 -AccountStatus "All" -GetManager:$false -ExportPath "C:\Temp\EntraUsersAll.csv"

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: Microsoft.Graph.Users module, Entra ID User.Read.All directory permissions.
    Change Log   :
        1.0 - Initial sanitized production release migrated from legacy AzureAD module to Microsoft Graph.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Specify whether to retrieve user manager details.")]
    [bool]$GetManager = $true,

    [Parameter(Mandatory = $false, HelpMessage = "Filter accounts by status: Enabled, Disabled, or All.")]
    [ValidateSet("Enabled", "Disabled", "All")]
    [string]$AccountStatus = "Enabled",

    [Parameter(Mandatory = $false, HelpMessage = "Specify path to save the exported CSV file.")]
    [ValidateNotNullOrEmpty()]
    [string]$ExportPath = "C:\Temp\ADUsers_$(Get-Date -Format 'MMM-dd-yyyy').csv",

    [Parameter(Mandatory = $false, HelpMessage = "Specify directory for execution log storage.")]
    [ValidateNotNullOrEmpty()]
    [string]$LogDirectory = "C:\Temp"
)

# --------------------------------------------------------------------------
# 1. PREREQUISITES & MODULE CHECKS
# --------------------------------------------------------------------------
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Warning "Running in non-elevated context. Ensure administrative privileges if module auto-installation is required."
}

$RequiredModule = "Microsoft.Graph.Users"

if (-not (Get-Module -ListAvailable -Name $RequiredModule)) {
    Write-Host "Required module '$RequiredModule' missing. Attempting installation for CurrentUser..." -ForegroundColor Yellow
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
$ScriptName = "EntraID_UsersExport"
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
    Write-Log "Connecting to Microsoft Graph SDK..." "INFO"
    Connect-MgGraph -Scopes "User.Read.All" -ErrorAction Stop | Out-Null

    Write-Log "Retrieving user accounts (Filter: $AccountStatus)..." "INFO"

    $Filter = switch ($AccountStatus) {
        "Enabled"  { "accountEnabled eq true" }
        "Disabled" { "accountEnabled eq false" }
        "All"      { $null }
    }

    $PropertySelect = @(
        'Id', 'DisplayName', 'UserPrincipalName', 'Mail', 'JobTitle',
        'Department', 'OfficeLocation', 'BusinessPhones', 'MobilePhone',
        'AccountEnabled', 'StreetAddress', 'City', 'PostalCode', 'State', 'Country'
    )

    $MgParams = @{
        All            = $true
        Property       = $PropertySelect
        ErrorAction    = "Stop"
    }

    if ($Filter) { $MgParams.Add("Filter", $Filter) }

    $Users = Get-MgUser @MgParams

    if (-not $Users) {
        Write-Log "No user records returned from Microsoft Graph query." "WARN"
        return
    }

    Write-Log "Retrieved $($Users.Count) user record(s). Processing metadata and manager details..." "INFO"

    $Results = [System.Collections.Generic.List[PSCustomObject]]::new()
    $Counter = 0
    $Total = $Users.Count

    foreach ($User in $Users) {
        $Counter++
        $Percent = [math]::Round(($Counter / $Total) * 100)
        Write-Progress -Activity "Processing Entra ID Users" -Status "User $Counter of $Total ($Percent%)" -PercentComplete $Percent

        $ManagerName = ""
        if ($GetManager) {
            try {
                $Manager = Get-MgUserManager -UserId $User.Id -ErrorAction SilentlyContinue
                if ($Manager) {
                    $ManagerName = $Manager.AdditionalProperties["displayName"]
                }
            }
            catch {
                Write-Log "Failed to retrieve manager for $($User.UserPrincipalName)" "WARN"
            }
        }

        $Phone = if ($User.BusinessPhones) { $User.BusinessPhones -join "; " } else { "" }

        $Results.Add([PSCustomObject]@{
            "Name"              = $User.DisplayName
            "UserPrincipalName" = $User.UserPrincipalName
            "Emailaddress"      = $User.Mail
            "Job title"         = $User.JobTitle
            "Manager"           = $ManagerName
            "Department"        = $User.Department
            "Office"            = $User.OfficeLocation
            "Phone"             = $Phone
            "Mobile"            = $User.MobilePhone
            "Enabled"           = if ($User.AccountEnabled) { "enabled" } else { "disabled" }
            "Street"            = $User.StreetAddress
            "City"              = $User.City
            "Postal code"       = $User.PostalCode
            "State"             = $User.State
            "Country"           = $User.Country
        })
    }

    Write-Progress -Activity "Processing Entra ID Users" -Completed

    $ExportDir = Split-Path -Path $ExportPath -Parent
    if (-not (Test-Path -Path $ExportDir)) {
        New-Item -Path $ExportDir -ItemType Directory -Force | Out-Null
    }

    $Results | Sort-Object -Property "Name" | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding utf8

    if ((Get-Item -Path $ExportPath).Length -gt 0) {
        Write-Log "SUCCESS! Exported $($Results.Count) user(s) to: $ExportPath" "INFO"
    }
    else {
        Write-Log "Failed to create or populate report at: $ExportPath" "ERROR"
    }
}
catch {
    Write-Log "CRITICAL ERROR during Entra ID export: $($_.Exception.Message)" "ERROR"
    exit 1
}
finally {
    Write-Log "Disconnecting Microsoft Graph session..." "INFO"
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
}