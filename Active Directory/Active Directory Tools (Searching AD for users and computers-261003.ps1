#requires -Version 5.1

<#
.SYNOPSIS
    Gathers remote computer inventory, local admin group membership, running processes, 
    and startup items, with remediation options for remote administration.

.DESCRIPTION
    Performs administrative inspection and maintenance tasks on target endpoints using CIM and Active Directory.
    Queries OS details, hardware specs, logged-on users, local administrators, installed applications, and startup items.
    Supports administrative actions such as terminating processes, removing local administrators, updating WSUS settings,
    and invoking system reboots. Exports detailed execution logs to C:\Temp with 7-day log rotation.

.PARAMETER ComputerName
    The target host name or IP address to inspect or manage. Defaults to the local computer name.

.PARAMETER Action
    The administrative diagnostic or management action to perform on the target computer.
    Supported actions: SystemInfo, LocalAdmins, Applications, Processes, StartupItems, 
    EndProcess, RemoveAdmin, ResetWSUS, RestartComputer.

.PARAMETER TargetItem
    Specifies the target item name (e.g., Process ID, Account Name, Application Name) required for remediation actions.

.PARAMETER LogDirectory
    The local directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Invoke-ComputerManagement.ps1 -ComputerName "WORKSTATION01" -Action SystemInfo

.EXAMPLE
    .\Invoke-ComputerManagement.ps1 -ComputerName "WORKSTATION01" -Action EndProcess -TargetItem "1234" -WhatIf

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: ActiveDirectory Module, Administrator Elevation, Remote Management Access (WinRM/CIM).
    Change Log   :
        1.0 - Initial sanitized production release refactored from legacy WinForms tool.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $false, Position = 0, HelpMessage = "Specify target computer name.")]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName = $env:COMPUTERNAME,

    [Parameter(Mandatory = $false, Position = 1, HelpMessage = "Specify administrative action.")]
    [ValidateSet("SystemInfo", "LocalAdmins", "Applications", "Processes", "StartupItems", "EndProcess", "RemoveAdmin", "ResetWSUS", "RestartComputer")]
    [string]$Action = "SystemInfo",

    [Parameter(Mandatory = $false, Position = 2, HelpMessage = "Specify target process ID or item name for remediation actions.")]
    [string]$TargetItem,

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
$ScriptName = "ComputerManagement"
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
# 3. HELPER FUNCTIONS
# --------------------------------------------------------------------------
function Test-HostConnection {
    param([string]$TargetHost)
    return (Test-Connection -ComputerName $TargetHost -Count 1 -Quiet -ErrorAction SilentlyContinue)
}

# --------------------------------------------------------------------------
# 4. SCRIPT EXECUTION
# --------------------------------------------------------------------------
try {
    Write-Log "Target Endpoint: $ComputerName | Action: $Action" "INFO"

    if (-not (Test-HostConnection -TargetHost $ComputerName)) {
        Write-Log "Could not contact or ping target computer: $ComputerName" "ERROR"
        exit 1
    }

    $CimSessionParams = @{ ComputerName = $ComputerName; ErrorAction = 'Stop' }

    switch ($Action) {
        "SystemInfo" {
            Write-Log "Gathering system information from $ComputerName..." "INFO"
            
            $OS   = Get-CimInstance @CimSessionParams -ClassName Win32_OperatingSystem
            $Comp = Get-CimInstance @CimSessionParams -ClassName Win32_ComputerSystem
            $BIOS = Get-CimInstance @CimSessionParams -ClassName Win32_BIOS
            $CPU  = Get-CimInstance @CimSessionParams -ClassName Win32_Processor
            $Disk = Get-CimInstance @CimSessionParams -ClassName Win32_LogicalDisk -Filter "DriveType=3"

            $ADComputer = Get-ADComputer -Identity $ComputerName -Properties DistinguishedName -ErrorAction SilentlyContinue

            [PSCustomObject]@{
                ComputerName     = $Comp.Name
                DomainLocation   = $ADComputer.DistinguishedName
                CurrentUser      = $Comp.UserName
                OperatingSystem  = $OS.Caption
                OSArchitecture   = $OS.OSArchitecture
                LastBootUpTime   = $OS.LastBootUpTime
                Manufacturer     = $Comp.Manufacturer
                Model            = $Comp.Model
                SerialNumber     = $BIOS.SerialNumber
                CPU              = $CPU.Name
                TotalRAM_GB      = [math]::Round(($Comp.TotalPhysicalMemory / 1GB), 2)
                FreeDiskSpace_GB = [math]::Round(($Disk[0].FreeSpace / 1GB), 2)
                TotalDiskSize_GB = [math]::Round(($Disk[0].Size / 1GB), 2)
            } | Format-List
        }

        "LocalAdmins" {
            Write-Log "Enumerating local Administrators group members on $ComputerName..." "INFO"
            $AdminGroup = [ADSI]"WinNT://$ComputerName/Administrators,group"
            $Members = $AdminGroup.psbase.Invoke('Members') | ForEach-Object {
                $Path = $_.GetType().InvokeMember('AdsPath', 'GetProperty', $null, $_, $null)
                $Parts = $Path.Split('/')
                [PSCustomObject]@{
                    ComputerName = $ComputerName
                    Domain       = $Parts[-2]
                    Name         = $Parts[-1]
                }
            }
            $Members | Format-Table -AutoSize
        }

        "Applications" {
            Write-Log "Gathering installed applications from $ComputerName..." "INFO"
            $Apps = Get-CimInstance @CimSessionParams -ClassName Win32_Product | Select-Object Name, Vendor, Version, InstallDate
            $Apps | Format-Table -AutoSize
        }

        "Processes" {
            Write-Log "Enumerating running processes on $ComputerName..." "INFO"
            $Procs = Get-CimInstance @CimSessionParams -ClassName Win32_Process | Select-Object ProcessId, Name, ExecutablePath
            $Procs | Sort-Object Name | Format-Table -AutoSize
        }

        "StartupItems" {
            Write-Log "Enumerating startup commands on $ComputerName..." "INFO"
            $Startups = Get-CimInstance @CimSessionParams -ClassName Win32_StartupCommand | Select-Object Caption, Command, Location, User
            $Startups | Format-Table -AutoSize
        }

        "EndProcess" {
            if ([string]::IsNullOrWhiteSpace($TargetItem)) {
                Write-Log "TargetItem parameter (Process ID) is required for EndProcess action." "ERROR"
                exit 1
            }

            Write-Log "Attempting to terminate Process ID $TargetItem on $ComputerName..." "WARN"
            if ($PSCmdlet.ShouldProcess("$ComputerName (PID: $TargetItem)", "Terminate Process")) {
                $Proc = Get-CimInstance @CimSessionParams -ClassName Win32_Process -Filter "ProcessId = '$TargetItem'"
                if ($Proc) {
                    Invoke-CimMethod -InputObject $Proc -MethodName Terminate | Out-Null
                    Write-Log "SUCCESS: Terminated process ID $TargetItem on $ComputerName." "INFO"
                }
                else {
                    Write-Log "Process ID $TargetItem not found on $ComputerName." "WARN"
                }
            }
        }

        "RemoveAdmin" {
            if ([string]::IsNullOrWhiteSpace($TargetItem)) {
                Write-Log "TargetItem parameter (Domain\Username or Username) is required for RemoveAdmin action." "ERROR"
                exit 1
            }

            Write-Log "Attempting to remove $TargetItem from local Administrators on $ComputerName..." "WARN"
            if ($PSCmdlet.ShouldProcess("$ComputerName - Administrators Group", "Remove $TargetItem")) {
                $AdminGroup = [ADSI]"WinNT://$ComputerName/Administrators,group"
                $AdminGroup.Remove("WinNT://$TargetItem")
                Write-Log "SUCCESS: Removed $TargetItem from local Administrators on $ComputerName." "INFO"
            }
        }

        "ResetWSUS" {
            Write-Log "Resetting WSUS Client authorization on $ComputerName..." "WARN"
            if ($PSCmdlet.ShouldProcess($ComputerName, "Reset WSUS Authorization & Client ID")) {
                Get-Service -ComputerName $ComputerName -Name "wuauserv" | Stop-Service -Force -ErrorAction SilentlyContinue
                
                $RegKey = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $ComputerName).OpenSubKey("SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\WindowsUpdate", $true)
                @("AccountDomainSid", "PingID", "SUSclientID", "SusClientIdValidation") | ForEach-Object {
                    if ($RegKey.GetValue($_)) { $RegKey.DeleteValue($_) }
                }

                Get-Service -ComputerName $ComputerName -Name "wuauserv" | Start-Service
                Invoke-CimMethod @CimSessionParams -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = "cmd.exe /c wuauclt.exe /resetauthorization /detectnow" } | Out-Null
                Write-Log "SUCCESS: Reset WSUS Client ID on $ComputerName." "INFO"
            }
        }

        "RestartComputer" {
            Write-Log "Requesting reboot for computer $ComputerName..." "WARN"
            if ($PSCmdlet.ShouldProcess($ComputerName, "Force Computer Restart")) {
                Restart-Computer -ComputerName $ComputerName -Force -ErrorAction Stop
                Write-Log "SUCCESS: Initiated restart command on $ComputerName." "INFO"
            }
        }
    }
}
catch {
    Write-Log "CRITICAL ERROR executing action '$Action' on $ComputerName: $($_.Exception.Message)" "ERROR"
    exit 1
}