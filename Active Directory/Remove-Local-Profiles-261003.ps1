#requires -Version 5.1

<#
.SYNOPSIS
    Removes specified local user profiles from a Windows system using CIM/WMI instances.

.DESCRIPTION
    Queries the Win32_UserProfile CIM class for local user profiles matching specified SIDs 
    and deletes both the profile registry entry and associated disk contents. Excludes special 
    system profiles from deletion. Includes native -WhatIf/-Confirm safety controls, execution 
    logging in C:\Temp, and automated 7-day log maintenance cleanup.

.PARAMETER SID
    An array of target Security Identifiers (SIDs) corresponding to the user profiles to be removed.

.PARAMETER ComputerName
    The target computer name to query and perform profile removal on. Defaults to the local machine ($env:COMPUTERNAME).

.PARAMETER LogDirectory
    The directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Remove-LocalUserProfiles.ps1 -SID "S-1-5-21-123456789-987654321-123456789-1001" -WhatIf

.EXAMPLE
    .\Remove-LocalUserProfiles.ps1 -SID "S-1-5-21-123456789-987654321-123456789-1001", "S-1-5-21-123456789-987654321-123456789-1002" -Confirm:$false

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: Local Administrative Privileges.
    Change Log   :
        1.0 - Initial sanitized production release (Migrated from Get-WmiObject to CIM).
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, HelpMessage = "Specify array of target profile SIDs to remove.")]
    [ValidateNotNullOrEmpty()]
    [string[]]$SID,

    [Parameter(Mandatory = $false, HelpMessage = "Specify target computer name.")]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName = $env:COMPUTERNAME,

    [Parameter(Mandatory = $false, HelpMessage = "Specify directory for execution log storage.")]
    [ValidateNotNullOrEmpty()]
    [string]$LogDirectory = "C:\Temp"
)

# --------------------------------------------------------------------------
# 1. PREREQUISITES & PRIVILEGE CHECKS
# --------------------------------------------------------------------------
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Error "This script requires administrative privileges to remove user profiles. Please run PowerShell as Administrator."
    exit 1
}

# --------------------------------------------------------------------------
# 2. LOGGING INITIALIZATION & HOUSEKEEPING
# --------------------------------------------------------------------------
$ScriptName = "Remove_LocalUserProfiles"
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
$CimSession = $null

try {
    Write-Log "Initializing local user profile removal routine on target computer: $ComputerName" "INFO"

    $CimParams = @{
        ClassName   = "Win32_UserProfile"
        ErrorAction = "Stop"
    }

    if ($ComputerName -ne $env:COMPUTERNAME) {
        Write-Log "Establishing CIM session to remote computer: $ComputerName..." "INFO"
        $CimSession = New-CimSession -ComputerName $ComputerName -ErrorAction Stop
        $CimParams.Add("CimSession", $CimSession)
    }

    $SuccessCount = 0
    $FailureCount = 0

    foreach ($TargetSID in $SID) {
        Write-Log "Processing target SID: $TargetSID" "INFO"

        try {
            # Query target profile instance
            $ProfileInstance = Get-CimInstance @CimParams | Where-Object { $_.SID -eq $TargetSID }

            if (-not $ProfileInstance) {
                Write-Log "No local user profile matching SID '$TargetSID' was found on '$ComputerName'." "WARN"
                continue
            }

            # Safety check: Protect Special profiles (e.g. System, LocalService, NetworkService)
            if ($ProfileInstance.Special) {
                Write-Log "SKIP: Profile SID '$TargetSID' ($($ProfileInstance.LocalPath)) is flagged as a Special System Profile and cannot be removed." "WARN"
                continue
            }

            $LocalPath = $ProfileInstance.LocalPath

            if ($PSCmdlet.ShouldProcess("Profile '$LocalPath' (SID: $TargetSID) on $ComputerName", "Remove local user profile")) {
                Write-Log "Removing profile at path '$LocalPath' (SID: $TargetSID)..." "INFO"
                
                Remove-CimInstance -InputObject $ProfileInstance -ErrorAction Stop
                Write-Log "SUCCESS: Removed profile '$LocalPath' (SID: $TargetSID)." "INFO"
                $SuccessCount++
            }
        }
        catch {
            Write-Log "ERROR removing profile for SID '$TargetSID': $($_.Exception.Message)" "ERROR"
            $FailureCount++
        }
    }

    Write-Log "Profile cleanup complete. Successful: $SuccessCount | Failed: $FailureCount" "INFO"
}
catch {
    Write-Log "CRITICAL ERROR during profile removal execution: $($_.Exception.Message)" "ERROR"
    exit 1
}
finally {
    if ($CimSession) {
        Write-Log "Closing active CIM session to $ComputerName..." "INFO"
        Remove-CimSession -CimSession $CimSession -ErrorAction SilentlyContinue
    }
}