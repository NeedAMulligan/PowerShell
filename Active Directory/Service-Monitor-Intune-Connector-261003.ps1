#requires -Version 5.1

<#
.SYNOPSIS
    Monitors, diagnoses, and automatically repairs the Intune ODJConnectorSvc on a Domain Controller.

.DESCRIPTION
    Performs a health check on the Intune Connector for Active Directory (ODJConnectorSvc).
    Validates service presence, tests network connectivity to required Microsoft endpoints, 
    verifies service account configuration, and automatically attempts service remediation if stopped.
    Writes execution logs to C:\Temp and performs automated 7-day log cleanup maintenance.

.PARAMETER ServiceName
    The target Windows Service name for the Intune ODJ Connector. Defaults to 'ODJConnectorSvc'.

.PARAMETER Endpoints
    An array of FQDN endpoints required for Microsoft Intune connectivity. 
    Defaults to 'manage.microsoft.com' and 'login.microsoftonline.com'.

.PARAMETER LogDirectory
    The local directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Monitor-ODJConnectorSvc.ps1

.EXAMPLE
    .\Monitor-ODJConnectorSvc.ps1 -ServiceName "ODJConnectorSvc" -Endpoints "manage.microsoft.com" -WhatIf

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: Local Administrative Privileges, NetTCPIP Module, RSAT / CIM Cmdlets.
    Change Log   :
        1.0 - Initial sanitized production release.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false, Position = 0, HelpMessage = "Specify target service name.")]
    [ValidateNotNullOrEmpty()]
    [string]$ServiceName = "ODJConnectorSvc",

    [Parameter(Mandatory = $false, HelpMessage = "Specify array of Microsoft Intune endpoints to test.")]
    [string[]]$Endpoints = @("manage.microsoft.com", "login.microsoftonline.com"),

    [Parameter(Mandatory = $false, HelpMessage = "Specify directory for execution log storage.")]
    [ValidateNotNullOrEmpty()]
    [string]$LogDirectory = "C:\Temp"
)

# --------------------------------------------------------------------------
# 1. PREREQUISITES & PRIVILEGE CHECKS
# --------------------------------------------------------------------------
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Error "This script requires administrative privileges to inspect and manage system services. Please run PowerShell as Administrator."
    exit 1
}

# --------------------------------------------------------------------------
# 2. LOGGING INITIALIZATION & HOUSEKEEPING
# --------------------------------------------------------------------------
$ScriptName = "Monitor_ODJConnectorSvc"
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
    Write-Log "Starting Intune ODJConnectorSvc Health Check and Diagnostics..." "INFO"

    # Step 1: Verify Service Installation
    $Service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

    if (-not $Service) {
        Write-Log "CRITICAL: Service '$ServiceName' is not installed on target system '$env:COMPUTERNAME'." "ERROR"
        return [PSCustomObject]@{
            ComputerName = $env:COMPUTERNAME
            ServiceName  = $ServiceName
            Installed    = $false
            Status       = "Not Installed"
            Remediated   = $false
            NetworkCheck = $false
        }
    }

    Write-Log "Discovered service '$ServiceName' (Current Status: $($Service.Status))." "INFO"

    # Step 2: Validate Service Account Context
    try {
        $CimSvc = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'" -ErrorAction Stop
        Write-Log "Service Account Context: $($CimSvc.StartName) | Start Mode: $($CimSvc.StartMode)" "INFO"
    }
    catch {
        Write-Log "Warning: Could not query CIM properties for service '$ServiceName': $($_.Exception.Message)" "WARN"
    }

    # Step 3: Network Endpoint Connectivity Check
    $NetworkSuccess = $true
    foreach ($Endpoint in $Endpoints) {
        try {
            $NetResult = Test-NetConnection -ComputerName $Endpoint -Port 443 -InformationLevel Quiet -ErrorAction SilentlyContinue
            if ($NetResult) {
                Write-Log "Connectivity to '$Endpoint' on port 443: SUCCESS" "INFO"
            }
            else {
                Write-Log "Connectivity to '$Endpoint' on port 443: FAILED" "WARN"
                $NetworkSuccess = $false
            }
        }
        catch {
            Write-Log "Error testing network connection to '$Endpoint': $($_.Exception.Message)" "WARN"
            $NetworkSuccess = $false
        }
    }

    # Step 4: Service Remediation Loop
    $Remediated = $false

    if ($Service.Status -ne 'Running') {
        Write-Log "Service status is '$($Service.Status)'. Attempting automatic start..." "WARN"

        if ($PSCmdlet.ShouldProcess($ServiceName, "Start Stopped Service")) {
            try {
                Start-Service -Name $ServiceName -ErrorAction Stop
                Start-Sleep -Seconds 5
                $Service.Refresh()

                if ($Service.Status -eq 'Running') {
                    Write-Log "SUCCESS: Service '$ServiceName' successfully started." "INFO"
                    $Remediated = $true
                }
                else {
                    Write-Log "CRITICAL: Service '$ServiceName' failed to remain running after start attempt." "ERROR"

                    # Check Event Log for Logon or Service Errors
                    $EventLogName = "Microsoft-Intune-ODJConnectorService/Admin"
                    try {
                        $RecentErrors = Get-WinEvent -LogName $EventLogName -MaxEvents 5 -ErrorAction SilentlyContinue | 
                            Where-Object { $_.LevelDisplayName -eq "Error" }

                        if ($RecentErrors) {
                            Write-Log "Recent Event Log errors found in '$EventLogName':" "ERROR"
                            foreach ($ErrEvent in $RecentErrors) {
                                Write-Log "  Event ID $($ErrEvent.Id) [$($ErrEvent.TimeCreated)]: $($ErrEvent.Message)" "ERROR"
                            }
                        }
                    }
                    catch {
                        Write-Log "Could not query Event Log path '$EventLogName'." "WARN"
                    }
                }
            }
            catch {
                Write-Log "ERROR: Failed to start service '$ServiceName': $($_.Exception.Message)" "ERROR"
            }
        }
    }
    else {
        Write-Log "Service '$ServiceName' is running normally. Health check passed." "INFO"
    }

    # Step 5: Structured Pipeline Return Object
    [PSCustomObject]@{
        ComputerName   = $env:COMPUTERNAME
        ServiceName    = $ServiceName
        Installed      = $true
        Status         = $Service.Status.ToString()
        Remediated     = $Remediated
        NetworkCheck   = $NetworkSuccess
        CheckTimestamp = Get-Date
    }
}
catch {
    Write-Log "CRITICAL ERROR during ODJConnectorSvc monitoring execution: $($_.Exception.Message)" "ERROR"
    exit 1
}
finally {
    Write-Log "ODJConnectorSvc Health Check procedure completed." "INFO"
}