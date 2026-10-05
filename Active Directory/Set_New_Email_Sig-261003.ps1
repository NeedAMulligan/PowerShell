#requires -Version 5.1

<#
.SYNOPSIS
    Updates the logon script (scriptPath) attribute for Active Directory user accounts across specified OUs or containers.

.DESCRIPTION
    Queries Active Directory user accounts within specified Search Base OUs or individual Distinguished Names 
    and updates their assigned logon script (scriptPath) attribute based on a configurable mapping table. 
    Includes native -WhatIf/-Confirm safety controls, execution logging in C:\Temp, and automated 7-day log maintenance cleanup.

.PARAMETER TargetMappings
    A Hashtable mapping target Organizational Unit Distinguished Names (or user CNs) to their designated VBScript logon script file names.

.PARAMETER LogDirectory
    The local directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    $Mappings = @{
        "OU=Density Technicians,OU=Employees,DC=contoso,DC=com" = "logon_standard.vbs"
        "OU=Marketing,OU=Office,OU=Employees,DC=contoso,DC=com"  = "logon_estimator.vbs"
    }
    .\Set-ADUserLoginScript.ps1 -TargetMappings $Mappings -WhatIf

.EXAMPLE
    .\Set-ADUserLoginScript.ps1 -TargetMappings $Mappings -Confirm:$false

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: RSAT Active Directory Tools module, Domain Administrator or Delegated Rights to modify user attributes.
    Change Log   :
        1.0 - Initial sanitized production release.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $false, Position = 0, HelpMessage = "Specify Hashtable mapping OU/CN Distinguished Names to target VBScript login files.")]
    [hashtable]$TargetMappings = @{
        "OU=Technicians,OU=Employees,DC=contoso,DC=com" = "standard_logon.vbs"
        "OU=Executive,OU=Employees,DC=contoso,DC=com"   = "standard_logon.vbs"
        "OU=Marketing,OU=Employees,DC=contoso,DC=com"   = "estimator_logon.vbs"
        "OU=Operations,OU=Employees,DC=contoso,DC=com"  = "logistics_logon.vbs"
    },

    [Parameter(Mandatory = $false, HelpMessage = "Specify directory for execution log storage.")]
    [ValidateNotNullOrEmpty()]
    [string]$LogDirectory = "C:\Temp"
)

# --------------------------------------------------------------------------
# 1. PREREQUISITES & PRIVILEGE CHECKS
# --------------------------------------------------------------------------
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Error "This script requires administrative privileges to modify Active Directory account properties. Please run PowerShell as Administrator."
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
$ScriptName = "AD_SetUserLoginScript"
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
    Write-Log "Initializing Active Directory User Logon Script (scriptPath) updates..." "INFO"

    if (-not $TargetMappings -or $TargetMappings.Count -eq 0) {
        Write-Log "No target mappings provided. Please supply a valid TargetMappings Hashtable." "WARN"
        return
    }

    Write-Log "Processing $($TargetMappings.Count) target container mapping entry(ies)..." "INFO"

    $OverallSuccess = 0
    $OverallFailure = 0

    foreach ($SearchBase in $TargetMappings.Keys) {
        $ScriptFile = $TargetMappings[$SearchBase]

        Write-Log "Processing Target Context: '$SearchBase' => Script: '$ScriptFile'" "INFO"

        try {
            # Retrieve users within target container/object
            $Users = Get-ADUser -Filter * -SearchBase $SearchBase -Properties ScriptPath -ErrorAction Stop

            if (-not $Users -or $Users.Count -eq 0) {
                Write-Log "No user objects found under context '$SearchBase'." "WARN"
                continue
            }

            foreach ($User in $Users) {
                $SamAccountName = $User.SamAccountName
                $UserDN         = $User.DistinguishedName

                if ($PSCmdlet.ShouldProcess("$SamAccountName ($UserDN)", "Set ScriptPath to '$ScriptFile'")) {
                    try {
                        Set-ADUser -Identity $UserDN -ScriptPath $ScriptFile -ErrorAction Stop
                        Write-Log "SUCCESS: Updated '$SamAccountName' scriptPath to '$ScriptFile'." "INFO"
                        $OverallSuccess++
                    }
                    catch {
                        Write-Log "ERROR: Failed to update '$SamAccountName' ($UserDN): $($_.Exception.Message)" "ERROR"
                        $OverallFailure++
                    }
                }
            }
        }
        catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
            Write-Log "ERROR: Search Base DN '$SearchBase' was not found in Active Directory." "ERROR"
            $OverallFailure++
        }
        catch {
            Write-Log "ERROR querying users under '$SearchBase': $($_.Exception.Message)" "ERROR"
            $OverallFailure++
        }
    }

    Write-Log "Logon script update process completed. Successful updates: $OverallSuccess | Failures: $OverallFailure" "INFO"
}
catch {
    Write-Log "CRITICAL ERROR during logon script assignment execution: $($_.Exception.Message)" "ERROR"
    exit 1
}