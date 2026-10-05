#requires -Version 5.1

<#
.SYNOPSIS
    Batch updates Active Directory user address properties and logon script paths across target OUs and accounts.

.DESCRIPTION
    Queries Active Directory user accounts within specified Organizational Units or targeted user lists,
    updates physical office address attributes (Street, City, State, Postal Code), and updates assigned
    logon script paths (ScriptPath). Includes native -WhatIf/-Confirm safety controls, execution logging in C:\Temp, 
    and automatic 7-day log maintenance.

.PARAMETER SearchBase
    The root Distinguished Name (DN) container under which target OUs reside. If omitted, queries relative to domain root.

.PARAMETER StreetAddress
    The street address to apply to target user accounts. Defaults to '5551 Wellington Rd.'.

.PARAMETER City
    The city to apply to target user accounts. Defaults to 'Gainesville'.

.PARAMETER State
    The state/province abbreviation to apply to target user accounts. Defaults to 'VA'.

.PARAMETER PostalCode
    The postal/ZIP code to apply to target user accounts. Defaults to '20155'.

.PARAMETER LogDirectory
    The local directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Update-ADUserProfilesAndScripts.ps1 -WhatIf

.EXAMPLE
    .\Update-ADUserProfilesAndScripts.ps1 -SearchBase "OU=Employees,DC=contoso,DC=com" -StreetAddress "100 Main St" -City "Reston" -State "VA" -PostalCode "20190" -Confirm:$false

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: RSAT Active Directory Tools module, Domain Administrator or Delegated Rights to modify user objects.
    Change Log   :
        1.0 - Initial sanitized production release.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $false, Position = 0, HelpMessage = "Specify the root Distinguished Name (DN) search base.")]
    [string]$SearchBase,

    [Parameter(Mandatory = $false, HelpMessage = "Specify the street address.")]
    [string]$StreetAddress = "5551 Wellington Rd.",

    [Parameter(Mandatory = $false, HelpMessage = "Specify the city.")]
    [string]$City = "Gainesville",

    [Parameter(Mandatory = $false, HelpMessage = "Specify the state or province.")]
    [string]$State = "VA",

    [Parameter(Mandatory = $false, HelpMessage = "Specify the postal code.")]
    [string]$PostalCode = "20155",

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
$ScriptName = "AD_UpdateUserProfiles"
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
    if ([string]::IsNullOrWhiteSpace($SearchBase)) {
        $SearchBase = (Get-ADDomain).DistinguishedName
    }

    Write-Log "Targeting Active Directory Root: $SearchBase" "INFO"

    # Define Organizational Units requiring Office Address Updates
    $AddressTargetOUs = @(
        "OU=Density Technicians",
        "OU=Executive",
        "OU=Foreman",
        "OU=Lab Technicians",
        "OU=Office",
        "OU=Operations",
        "OU=Plant Operators",
        "OU=Shop",
        "OU=STC",
        "OU=Administrative Users"
    )

    # 1. Update Office Address Properties
    Write-Log "Beginning Office Address Updates across target OUs..." "INFO"
    foreach ($RelativeOU in $AddressTargetOUs) {
        $TargetOUDN = if ($RelativeOU -like "*DC=*") { $RelativeOU } else { "$RelativeOU,$SearchBase" }

        Write-Log "Processing Address Updates for OU: $TargetOUDN" "INFO"

        try {
            $Users = Get-ADUser -Filter * -SearchBase $TargetOUDN -Properties StreetAddress, City, State, PostalCode -ErrorAction Stop

            foreach ($User in $Users) {
                if ($PSCmdlet.ShouldProcess($User.SamAccountName, "Update Address: Street='$StreetAddress', City='$City', State='$State', Zip='$PostalCode'")) {
                    Set-ADUser -Identity $User.DistinguishedName -StreetAddress $StreetAddress -City $City -State $State -PostalCode $PostalCode -ErrorAction Stop
                    Write-Log "SUCCESS: Updated address for user '$($User.SamAccountName)'." "INFO"
                }
            }
        }
        catch {
            Write-Log "ERROR querying or updating OU '$TargetOUDN': $($_.Exception.Message)" "ERROR"
        }
    }

    # 2. Update Logon Script Paths
    Write-Log "Beginning Logon Script Path updates..." "INFO"

    # Define Map of Target OUs/Containers to Script Files
    $ScriptMappings = @(
        @{ Target = "OU=Density Technicians"; Script = "bristowlogon2.vbs" },
        @{ Target = "OU=Executive";          Script = "bristowlogon2.vbs" },
        @{ Target = "OU=Accounting,OU=Office"; Script = "bristowlogon2.vbs" },
        @{ Target = "OU=Human Resources,OU=Office"; Script = "bristowlogon2.vbs" },
        @{ Target = "OU=Marketing,OU=Office"; Script = "estimatorlogon2.vbs" },
        @{ Target = "OU=Safety,OU=Office";    Script = "bristowlogon2.vbs" },
        @{ Target = "OU=Reception,OU=Office"; Script = "bristowlogon2.vbs" },
        @{ Target = "OU=Operations";          Script = "bristowlogon2.vbs" },
        @{ Target = "OU=STC";                 Script = "Trucking2.vbs" }
    )

    foreach ($Mapping in $ScriptMappings) {
        $TargetOUDN = "$($Mapping.Target),$SearchBase"
        $ScriptFile = $Mapping.Script

        Write-Log "Setting ScriptPath '$ScriptFile' for users in: $TargetOUDN" "INFO"

        try {
            $Users = Get-ADUser -Filter * -SearchBase $TargetOUDN -Properties ScriptPath -ErrorAction Stop

            foreach ($User in $Users) {
                if ($PSCmdlet.ShouldProcess($User.SamAccountName, "Set ScriptPath='$ScriptFile'")) {
                    Set-ADUser -Identity $User.DistinguishedName -ScriptPath $ScriptFile -ErrorAction Stop
                    Write-Log "SUCCESS: Assigned script '$ScriptFile' to '$($User.SamAccountName)'." "INFO"
                }
            }
        }
        catch {
            Write-Log "ERROR updating script path for OU '$TargetOUDN': $($_.Exception.Message)" "ERROR"
        }
    }

    Write-Log "Active Directory profile and logon script updates completed." "INFO"
}
catch {
    Write-Log "CRITICAL ERROR during execution: $($_.Exception.Message)" "ERROR"
    exit 1
}