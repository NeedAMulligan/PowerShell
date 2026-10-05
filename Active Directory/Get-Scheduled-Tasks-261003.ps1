#requires -Version 5.1

<#
.SYNOPSIS
    Audits non-standard auto-start services and PowerShell-related scheduled tasks on a target computer via WinRM.

.DESCRIPTION
    Establishes a WinRM session to a local or remote target computer to inspect auto-start system services running 
    under non-local accounts, as well as scheduled tasks configured to execute PowerShell commands. 
    Outputs structured custom objects directly to the pipeline, logs execution activity to C:\Temp, 
    and automatically cleans up log files older than 7 days.

.PARAMETER ComputerName
    The hostname or IP address of the target computer to audit.

.PARAMETER Credential
    Optional PSCredential object used to authenticate against the remote computer. If omitted, uses current context credentials.

.PARAMETER ExportPath
    Optional file path to export audit results to CSV format.

.PARAMETER LogDirectory
    The local directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Audit-ServiceAndScheduledTasks.ps1 -ComputerName "SERVER01.contoso.com"

.EXAMPLE
    $Cred = Get-Credential
    .\Audit-ServiceAndScheduledTasks.ps1 -ComputerName "SERVER01" -Credential $Cred -ExportPath "C:\Temp\AuditReport.csv"

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: WinRM Enabled on Target, Administrative Privileges.
    Change Log   :
        1.0 - Initial sanitized production release.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, HelpMessage = "Specify target computer hostname or IP address.")]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName,

    [Parameter(Mandatory = $false, HelpMessage = "Specify alternate credentials for remote authentication.")]
    [PSCredential]$Credential,

    [Parameter(Mandatory = $false, HelpMessage = "Optional CSV output file path.")]
    [string]$ExportPath,

    [Parameter(Mandatory = $false, HelpMessage = "Specify directory for execution log storage.")]
    [ValidateNotNullOrEmpty()]
    [string]$LogDirectory = "C:\Temp"
)

# --------------------------------------------------------------------------
# 1. PREREQUISITES & PRIVILEGE CHECKS
# --------------------------------------------------------------------------
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Warning "Running in non-elevated context. Ensure proper administrative rights to query target remote host."
}

# --------------------------------------------------------------------------
# 2. LOGGING INITIALIZATION & HOUSEKEEPING
# --------------------------------------------------------------------------
$ScriptName = "Audit_ServiceAndScheduledTasks"
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
$Session = $null

try {
    Write-Log "Initializing service and scheduled task audit for target host: $ComputerName" "INFO"

    $SessionParams = @{
        ComputerName = $ComputerName
        ErrorAction  = "Stop"
    }
    if ($Credential) {
        $SessionParams.Add("Credential", $Credential)
    }

    Write-Log "Establishing PSSession to $ComputerName..." "INFO"
    $Session = New-PSSession @SessionParams

    # Define Remote ScriptBlock
    $RemoteScriptBlock = {
        # 1. Audit Services running under non-standard accounts
        $Services = Get-CimInstance -ClassName Win32_Service -ErrorAction Stop | 
            Where-Object { 
                $_.StartMode -eq 'Auto' -and 
                $_.StartName -notlike '*local*' -and 
                $_.StartName -notlike '*NT AU*' -and 
                $_.StartName -notlike '*NT Authority*'
            } | 
            Select-Object @{Name = 'AuditType'; Expression = { 'Service' }},
                          Name, DisplayName, State, StartMode, StartName,
                          @{Name = 'Action/Command'; Expression = { $_.PathName }}

        # 2. Audit Scheduled Tasks executing PowerShell
        $Tasks = [System.Collections.Generic.List[PSCustomObject]]::new()
        
        try {
            $RawTasks = schtasks.exe /query /V /FO CSV | ConvertFrom-Csv -ErrorAction Stop | 
                Where-Object { $_.TaskName -ne "TaskName" -and $_.'Task To Run' -like "*powershell*" }

            foreach ($Task in $RawTasks) {
                $Tasks.Add([PSCustomObject]@{
                    AuditType        = 'ScheduledTask'
                    Name             = Split-Path -Path $Task.TaskName -Leaf
                    DisplayName      = $Task.TaskName
                    State            = $Task.Status
                    StartMode        = $Task.'Schedule Type'
                    StartName        = $Task.'Run As User'
                    'Action/Command' = $Task.'Task To Run'
                })
            }
        }
        catch {
            # Fallback handling if schtasks output format differs
        }

        [PSCustomObject]@{
            Services       = $Services
            ScheduledTasks = $Tasks
        }
    }

    Write-Log "Executing audit ScriptBlock on remote host..." "INFO"
    $AuditResult = Invoke-Command -Session $Session -ScriptBlock $RemoteScriptBlock -ErrorAction Stop

    $CombinedResults = [System.Collections.Generic.List[PSCustomObject]]::new()

    if ($AuditResult.Services) {
        foreach ($Svc in $AuditResult.Services) { $CombinedResults.Add($Svc) }
    }
    if ($AuditResult.ScheduledTasks) {
        foreach ($Tsk in $AuditResult.ScheduledTasks) { $CombinedResults.Add($Tsk) }
    }

    Write-Log "Audit complete. Found $($AuditResult.Services.Count) service(s) and $($AuditResult.ScheduledTasks.Count) scheduled task(s)." "INFO"

    # Handle Export if specified
    if (-not [string]::IsNullOrWhiteSpace($ExportPath)) {
        $ExportDir = Split-Path -Path $ExportPath -Parent
        if ($ExportDir -and (-not (Test-Path -Path $ExportDir))) {
            New-Item -Path $ExportDir -ItemType Directory -Force | Out-Null
        }
        $CombinedResults | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding utf8
        Write-Log "SUCCESS: Exported audit results to: $ExportPath" "INFO"
    }

    # Pipeline output
    $CombinedResults
}
catch {
    Write-Log "CRITICAL ERROR during service and task audit on host '$ComputerName': $($_.Exception.Message)" "ERROR"
    exit 1
}
finally {
    if ($Session) {
        Write-Log "Closing active PSSession to $ComputerName..." "INFO"
        Remove-PSSession -Session $Session -ErrorAction SilentlyContinue
    }
}