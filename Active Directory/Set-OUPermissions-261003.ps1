#requires -Version 5.1

<#
.SYNOPSIS
    Delegates computer object creation and management permissions on a target Active Directory Organizational Unit (OU).

.DESCRIPTION
    Delegates Active Directory permissions to a specified user or service account allowing full creation, 
    deletion, password reset, and principal management rights for computer objects within a specified target OU. 
    Includes native -WhatIf/-Confirm safety controls, execution logging in C:\Temp, and automated 7-day log maintenance cleanup.

.PARAMETER Account
    The sAMAccountName, UserPrincipalName, or Identity of the user/service account receiving delegated rights.

.PARAMETER TargetOU
    The Distinguished Name (DN) or relative path of the target Organizational Unit (e.g., 'OU=Workstations,DC=contoso,DC=com').

.PARAMETER LogDirectory
    The local directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Set-ADComputerOUDelegation.ps1 -Account "svc_deployment" -TargetOU "OU=Workstations,DC=contoso,DC=com" -WhatIf

.EXAMPLE
    .\Set-ADComputerOUDelegation.ps1 -Account "jdoe" -TargetOU "OU=Servers,DC=contoso,DC=com" -Confirm:$false

.NOTES
    Author       : System Administrator / Sanitized (Refactored from Mikael Nystrom & Johan Arwidmark)
    Prerequisites: RSAT Active Directory Tools module, Domain Administrator or Delegated Permissions rights.
    Change Log   :
        1.0 - Initial sanitized production release.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName =$true, HelpMessage = "Specify the target account receiving delegated permissions.")]
    [ValidateNotNullOrEmpty()]
    [string]$Account,

    [Parameter(Mandatory = $true, Position = 1, ValueFromPipelineByPropertyName =$true, HelpMessage = "Specify the target Organizational Unit (OU) Distinguished Name.")]
    [ValidateNotNullOrEmpty()]
    [string]$TargetOU,

    [Parameter(Mandatory = $false, HelpMessage = "Specify directory for execution log storage.")]
    [ValidateNotNullOrEmpty()]
    [string]$LogDirectory = "C:\Temp"
)

# --------------------------------------------------------------------------
# 1. PREREQUISITES & PRIVILEGE CHECKS
# --------------------------------------------------------------------------
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Error "This script requires administrative privileges to modify Active Directory Security Descriptors. Please run PowerShell as Administrator."
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
$ScriptName = "Delegate_ADComputerOUManagement"
$DateStamp  = Get-Date -Format "yyyyMMdd_HHmmss"

if (-not (Test-Path -Path $LogDirectory)) {
    New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
}

# Log rotation: Remove log files older than 7 days from C:\Temp
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
    Write-Log "Initializing Computer Object Management OU Delegation routine..." "INFO"

    # Validate and Resolve Target OU Distinguished Name
    $CurrentDomain = Get-ADDomain -ErrorAction Stop
    $OrganizationalUnitDN =$TargetOU

    if ($TargetOU -notlike "*DC=*") {
        $OrganizationalUnitDN = "$TargetOU,$($CurrentDomain.DistinguishedName)"
        Write-Log "Appended current domain root DN context: $OrganizationalUnitDN" "INFO"
    }

    # Verify OU Existence
    try {
        $OuObject = Get-ADOrganizationalUnit -Identity$OrganizationalUnitDN -ErrorAction Stop
    }
    catch {
        Write-Log "ERROR: Target Organizational Unit '$OrganizationalUnitDN' was not found in Active Directory." "ERROR"
        exit 1
    }

    # Verify Account Existence
    try {
        $SearchAccount = Get-ADUser -Identity$Account -ErrorAction Stop
        $SAM =$SearchAccount.SamAccountName
        $UserAccount = "$($CurrentDomain.NetBIOSName)\$SAM"
    }
    catch {
        Write-Log "ERROR: Target user account '$Account' was not found in Active Directory." "ERROR"
        exit 1
    }

    Write-Log "Target Account: $UserAccount" "INFO"
    Write-Log "Target OU DN : $OrganizationalUnitDN" "INFO"

    # Define DSACLS Delegation Entry Rules
    $DsaclsRules = @(
        "/G `"$UserAccount`:CCDC;Computer`" /I:T",
        "/G `"$UserAccount`:LC;;Computer`" /I:S",
        "/G `"$UserAccount`:RC;;Computer`" /I:S",
        "/G `"$UserAccount`:WD;;Computer`" /I:S",
        "/G `"$UserAccount`:WP;;Computer`" /I:S",
        "/G `"$UserAccount`:RP;;Computer`" /I:S",
        "/G `"$UserAccount`:CA;Reset Password;Computer`" /I:S",
        "/G `"$UserAccount`:CA;Change Password;Computer`" /I:S",
        "/G `"$UserAccount`:WS;Validated write to service principal name;Computer`" /I:S",
        "/G `"$UserAccount`:WS;Validated write to DNS host name;Computer`" /I:S"
    )

    if ($PSCmdlet.ShouldProcess("$OrganizationalUnitDN", "Delegate Computer Object Creation/Management Rights to $UserAccount")) {
        Write-Log "Applying security descriptor modifications via dsacls..." "INFO"

        foreach ($Rule in $DsaclsRules) {$Command = "dsacls.exe `"$OrganizationalUnitDN`" $Rule"
            try {
                $Process = Start-Process -FilePath "dsacls.exe" -ArgumentList "`"$OrganizationalUnitDN`" $Rule" -Wait -NoNewWindow -PassThru -ErrorAction Stop
                if ($Process.ExitCode -eq 0) {
                    Write-Log "SUCCESS: Applied ACE rule: $Rule" "INFO"
                }
                else {
                    Write-Log "WARNING: dsacls returned non-zero exit code ($($Process.ExitCode)) for rule:$Rule" "WARN"
                }
            }
            catch {
                Write-Log "ERROR executing dsacls for rule '$Rule': $($_.Exception.Message)" "ERROR"
            }
        }

        Write-Log "OU Delegation assignment completed successfully for $UserAccount." "INFO"
    }
}
catch {
    Write-Log "CRITICAL ERROR during OU delegation execution: $($_.Exception.Message)" "ERROR"
    exit 1
}