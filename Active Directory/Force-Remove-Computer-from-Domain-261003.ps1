#requires -Version 5.1

<#
.SYNOPSIS
    Removes the local computer from an Active Directory domain and optionally restarts the machine.

.DESCRIPTION
    Unjoins the local computer from its active Active Directory domain using provided domain administrative credentials.
    Outputs execution logs to C:\Temp, supports native -WhatIf/-Confirm safety controls, and automatically performs 
    a 7-day log maintenance cleanup prior to execution.

.PARAMETER UnjoinCredential
    A PSCredential object containing domain administrative credentials authorized to unjoin the machine from Active Directory.

.PARAMETER Restart
    Switch parameter specifying whether to restart the computer immediately after unjoining the domain. Defaults to $false.

.PARAMETER LogDirectory
    The directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    $Cred = Get-Credential
    .\Remove-ComputerFromDomain.ps1 -UnjoinCredential $Cred -WhatIf

.EXAMPLE
    $Cred = Get-Credential
    .\Remove-ComputerFromDomain.ps1 -UnjoinCredential $Cred -Restart -Confirm:$false

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: Local Administrator Elevation, Domain Administrative Credentials.
    Change Log   :
        1.0 - Initial sanitized production release.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Specify credentials authorized to unjoin the computer from the domain.")]
    [System.Management.Automation.PSCredential]$UnjoinCredential,

    [Parameter(Mandatory = $false, HelpMessage = "Specify whether to restart the computer after unjoining.")]
    [switch]$Restart,

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

# --------------------------------------------------------------------------
# 2. LOGGING INITIALIZATION & HOUSEKEEPING
# --------------------------------------------------------------------------
$ScriptName = "Remove_ComputerDomain"
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
    $ComputerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    
    if (-not $ComputerSystem.PartOfDomain) {
        Write-Log "The computer '$($env:COMPUTERNAME)' is currently in a Workgroup and not joined to a domain." "WARN"
        return
    }

    $DomainName = $ComputerSystem.Domain
    Write-Log "Target Machine: $($env:COMPUTERNAME) | Current Domain: $DomainName" "INFO"

    if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Unjoin from Domain '$DomainName'")) {
        Write-Log "Attempting to unjoin '$($env:COMPUTERNAME)' from domain '$DomainName'..." "WARN"

        $RemoveParams = @{
            UnjoinDomainCredential = $UnjoinCredential
            Force                  = $true
            Verbose                = $true
            ErrorAction            = "Stop"
        }

        if ($Restart) {
            $RemoveParams.Add("Restart", $true)
            Write-Log "Restart switch specified. Machine will reboot upon successful unjoin." "INFO"
        }

        Remove-Computer @RemoveParams
        Write-Log "SUCCESS: Machine successfully unjoined from domain '$DomainName'." "INFO"
    }
}
catch {
    Write-Log "CRITICAL ERROR while unjoining domain: $($_.Exception.Message)" "ERROR"
    exit 1
}