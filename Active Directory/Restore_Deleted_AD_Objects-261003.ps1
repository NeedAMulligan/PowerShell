#requires -Version 5.1

<#
.SYNOPSIS
    Restores deleted Active Directory user and computer objects from the Active Directory Recycle Bin.

.DESCRIPTION
    Queries Active Directory deleted objects container for tombstoned user or computer objects matching 
    specified search patterns and restores them using Restore-ADObject. Includes native -WhatIf/-Confirm 
    safety controls, execution logging in C:\Temp, and automated 7-day log maintenance cleanup.

.PARAMETER ComputerName
    The target computer name or wildcard pattern to restore from the Recycle Bin (e.g., 'SPC-00247*').

.PARAMETER UserName
    The target username or wildcard pattern to restore from the Recycle Bin (e.g., 'jdoe*').

.PARAMETER LogDirectory
    The local directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Restore-ADDeletedObjects.ps1 -ComputerName "SPC-00247*" -WhatIf

.EXAMPLE
    .\Restore-ADDeletedObjects.ps1 -UserName "jdoe" -Confirm:$false

.EXAMPLE
    .\Restore-ADDeletedObjects.ps1 -ComputerName "WORKSTATION01" -UserName "jdoe"

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: RSAT Active Directory Tools module, AD Recycle Bin Optional Feature Enabled, Domain Admin privileges.
    Change Log   :
        1.0 - Initial sanitized production release.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $false, Position = 0, HelpMessage = "Specify computer name or wildcard pattern to restore.")]
    [string]$ComputerName,

    [Parameter(Mandatory = $false, Position = 1, HelpMessage = "Specify user name or wildcard pattern to restore.")]
    [string]$UserName,

    [Parameter(Mandatory = $false, HelpMessage = "Specify directory for execution log storage.")]
    [ValidateNotNullOrEmpty()]
    [string]$LogDirectory = "C:\Temp"
)

# --------------------------------------------------------------------------
# 1. PREREQUISITES & PRIVILEGE CHECKS
# --------------------------------------------------------------------------
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Error "This script requires administrative privileges to restore deleted Active Directory objects. Please run PowerShell as Administrator."
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
$ScriptName = "AD_RestoreDeletedObjects"
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
    if ([string]::IsNullOrWhiteSpace($ComputerName) -and [string]::IsNullOrWhiteSpace($UserName)) {
        Write-Log "No ComputerName or UserName criteria specified. Please supply at least one target parameter." "WARN"
        return
    }

    Write-Log "Initializing Active Directory Recycle Bin Restoration Audit..." "INFO"

    $ObjectsToRestore = [System.Collections.Generic.List[PSCustomObject]]::new()

    # 1. Query Computer Objects
    if (-not [string]::IsNullOrWhiteSpace($ComputerName)) {
        Write-Log "Searching Active Directory Recycle Bin for deleted computer objects matching pattern '$ComputerName'..." "INFO"
        try {
            $DeletedComputers = Get-ADObject -Filter 'isDeleted -eq $true' -IncludeDeletedObjects -ErrorAction Stop | 
                Where-Object { $_.ObjectClass -eq "computer" -and $_.Name -like $ComputerName }

            foreach ($Comp in $DeletedComputers) {
                $ObjectsToRestore.Add($Comp)
            }
        }
        catch {
            Write-Log "Error querying deleted computer objects: $($_.Exception.Message)" "ERROR"
        }
    }

    # 2. Query User Objects
    if (-not [string]::IsNullOrWhiteSpace($UserName)) {
        Write-Log "Searching Active Directory Recycle Bin for deleted user objects matching pattern '$UserName'..." "INFO"
        try {
            $DeletedUsers = Get-ADObject -Filter 'isDeleted -eq $true' -IncludeDeletedObjects -ErrorAction Stop | 
                Where-Object { $_.ObjectClass -eq "user" -and $_.Name -like $UserName }

            foreach ($User in $DeletedUsers) {
                $ObjectsToRestore.Add($User)
            }
        }
        catch {
            Write-Log "Error querying deleted user objects: $($_.Exception.Message)" "ERROR"
        }
    }

    if ($ObjectsToRestore.Count -eq 0) {
        Write-Log "No matching deleted Active Directory objects were found in the Recycle Bin." "WARN"
        return
    }

    Write-Log "Found $($ObjectsToRestore.Count) deleted object(s) targeted for restoration." "INFO"

    $SuccessCount = 0
    $FailureCount = 0

    foreach ($ADObj in $ObjectsToRestore) {
        $ObjName  = $ADObj.Name
        $ObjClass = $ADObj.ObjectClass
        $ObjGuid  = $ADObj.ObjectGUID

        if ($PSCmdlet.ShouldProcess("Object '$ObjName' (Class: $ObjClass, GUID: $ObjGuid)", "Restore Active Directory Object from Recycle Bin")) {
            try {
                Restore-ADObject -Identity $ADObj -ErrorAction Stop
                Write-Log "SUCCESS: Restored $ObjClass object '$ObjName' (GUID: $ObjGuid)." "INFO"
                $SuccessCount++
            }
            catch {
                Write-Log "ERROR: Failed to restore $ObjClass object '$ObjName': $($_.Exception.Message)" "ERROR"
                $FailureCount++
            }
        }
    }

    Write-Log "Restoration process complete. Successful: $SuccessCount | Failed: $FailureCount" "INFO"
}
catch {
    Write-Log "CRITICAL ERROR during Active Directory object restoration execution: $($_.Exception.Message)" "ERROR"
    exit 1
}