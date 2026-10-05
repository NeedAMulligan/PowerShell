#requires -Version 5.1

<#
.SYNOPSIS
    Tests, repairs, and resets the Active Directory secure channel trust relationship for the local computer.

.DESCRIPTION
    Verifies the secure channel trust relationship between the local workstation/server and Active Directory. 
    Optionally resets the local computer machine account password, performs secure channel repair using 
    Test-ComputerSecureChannel, and verifies the active connection using nltest. Writes execution logs to C:\Temp 
    and automatically performs 7-day log cleanup maintenance.

.PARAMETER Server
    Optional target Domain Controller FQDN or hostname to process the machine password reset and secure channel repair against.

.PARAMETER Credential
    PSCredential object containing administrative credentials authorized to perform secure channel repairs in Active Directory.

.PARAMETER ResetPassword
    Switch parameter to explicitly trigger Reset-ComputerMachinePassword before repairing the secure channel.

.PARAMETER LogDirectory
    The local directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Repair-SecureChannel.ps1 -Credential (Get-Credential)

.EXAMPLE
    .\Repair-SecureChannel.ps1 -Server "dc01.contoso.com" -Credential (Get-Credential) -ResetPassword -WhatIf

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: Local Administrative Privileges, Domain Administrative Credentials, Active Directory Access.
    Change Log   :
        1.0 - Initial sanitized production release.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $false, Position = 0, HelpMessage = "Specify target Domain Controller hostname or FQDN.")]
    [string]$Server,

    [Parameter(Mandatory = $false, Position = 1, HelpMessage = "Specify domain administrative credentials for secure channel repair.")]
    [PSCredential]$Credential,

    [Parameter(Mandatory = $false, HelpMessage = "Switch to reset local machine account password.")]
    [switch]$ResetPassword,

    [Parameter(Mandatory = $false, HelpMessage = "Specify directory for execution log storage.")]
    [ValidateNotNullOrEmpty()]
    [string]$LogDirectory = "C:\Temp"
)

# --------------------------------------------------------------------------
# 1. PREREQUISITES & PRIVILEGE CHECKS
# --------------------------------------------------------------------------
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Error "This script requires administrative privileges to repair secure channel relationships. Please run PowerShell as Administrator."
    exit 1
}

# --------------------------------------------------------------------------
# 2. LOGGING INITIALIZATION & HOUSEKEEPING
# --------------------------------------------------------------------------
$ScriptName = "Repair_SecureChannel"
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
    Write-Log "Initializing Secure Channel diagnostic and repair routine for host '$env:COMPUTERNAME'..." "INFO"

    # Step 1: Optional Machine Account Password Reset
    if ($ResetPassword) {
        if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Reset Computer Machine Password")) {
            Write-Log "Resetting computer machine password..." "INFO"
            
            $ResetParams = @{ ErrorAction = "Stop" }
            if (-not [string]::IsNullOrWhiteSpace($Server)) { $ResetParams.Add("Server", $Server) }
            if ($Credential) { $ResetParams.Add("Credential", $Credential) }

            try {
                Reset-ComputerMachinePassword @ResetParams
                Write-Log "SUCCESS: Machine password successfully reset." "INFO"
            }
            catch {
                Write-Log "ERROR: Failed to reset machine account password: $($_.Exception.Message)" "ERROR"
            }
        }
    }

    # Step 2: Repair Secure Channel
    if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Repair Active Directory Secure Channel")) {
        Write-Log "Executing secure channel repair (Test-ComputerSecureChannel -Repair)..." "INFO"

        $RepairParams = @{
            Repair      = $true
            ErrorAction = "Stop"
        }
        if ($Credential) { $RepairParams.Add("Credential", $Credential) }

        try {
            $RepairStatus = Test-ComputerSecureChannel @RepairParams
            if ($RepairStatus) {
                Write-Log "SUCCESS: Secure channel repair returned TRUE." "INFO"
            }
            else {
                Write-Log "WARNING: Secure channel repair returned FALSE." "WARN"
            }
        }
        catch {
            Write-Log "ERROR: Failed during secure channel repair execution: $($_.Exception.Message)" "ERROR"
        }
    }

    # Step 3: Verify Secure Channel with nltest
    Write-Log "Verifying secure channel state using native 'nltest'..." "INFO"
    
    $DomainName = $env:USERDNSDOMAIN
    if ([string]::IsNullOrWhiteSpace($DomainName)) {
        $DomainName = $env:USERDOMAIN
    }

    if (-not [string]::IsNullOrWhiteSpace($DomainName)) {
        $NltestOutput = & nltest /sc_verify:$DomainName 2>&1
        foreach ($Line in $NltestOutput) {
            Write-Log "nltest: $Line" "INFO"
        }
    }
    else {
        Write-Log "Could not resolve local domain name context for nltest verification." "WARN"
    }

    Write-Log "Secure channel diagnostic and repair procedure completed." "INFO"
}
catch {
    Write-Log "CRITICAL ERROR during secure channel repair procedure: $($_.Exception.Message)" "ERROR"
    exit 1
}