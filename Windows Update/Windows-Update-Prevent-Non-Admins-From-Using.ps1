<#
.SYNOPSIS
    Forcefully restricts non-administrator access to Windows Update settings.
    
.DESCRIPTION
    MSP-grade script for ManageEngine Endpoint Central. 
    Hides the Windows Update UI and disables manual check for updates.
    FORCEFULLY closes the Settings app if open to ensure policy application.

.PARAMETER Action
    Determines if the policy should be 'Apply' (Restrict) or 'Rollback' (Allow). Default is Apply.

.EXIT CODES
    0 - Success
    1 - General Error
    2 - Insufficient Privileges
    3 - Process Termination Failed
    4 - Prerequisite Failure (Service State)
#>

[CmdletBinding()]
param (
    [ValidateSet("Apply", "Rollback")]
    [string]$Action = "Apply"
)

# --- Variables ---
$ScriptName       = "Restrict-WinUpdateUI_Enforced"
$LogDirectory     = "C:\Temp"
$Timestamp        = Get-Date -Format "yyyyMMdd_HHmmss"
$LogPath          = Join-Path $LogDirectory "$($ScriptName)_$($Timestamp).log"
$ConflictProcess  = "SystemSettings" 

$RegistryPolicies = @(
    @{
        Path  = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
        Name  = "SettingsPageVisibility"
        Value = "hide:windowsupdate"
        Type  = "String"
    },
    @{
        Path  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
        Name  = "NoWindowsUpdate"
        Value = 1
        Type  = "DWord"
    },
    @{
        Path  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
        Name  = "AUOptions"
        Value = 2 
        Type  = "DWord"
    }
)

# --- Functions ---

function Write-MSPLog {
    param([string]$Message)
    $Entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
    $Entry | Out-File -FilePath $LogPath -Append
}

function Test-IsAdmin {
    $identifier = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identifier)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# --- Execution Logic ---

if (!(Test-Path $LogDirectory)) { New-Item -Path $LogDirectory -ItemType Directory | Out-Null }

Write-MSPLog "Starting script: $Action Mode (Enforced)"

if (-not (Test-IsAdmin)) {
    Write-MSPLog "ERROR: Script must be run with Administrator/SYSTEM privileges."
    exit 2
}

# 3. Force Close Conflict Process
$ActiveProcess = Get-Process -Name $ConflictProcess -ErrorAction SilentlyContinue
if ($ActiveProcess) {
    Write-MSPLog "ENFORCEMENT: $ConflictProcess detected. Terminating process to apply policy..."
    try {
        $ActiveProcess | Stop-Process -Force -ErrorAction Stop
        Start-Sleep -Seconds 2 # Buffer for OS to release registry handles
        Write-MSPLog "SUCCESS: Process terminated."
    } catch {
        Write-MSPLog "ERROR: Failed to terminate $ConflictProcess. $($_.Exception.Message)"
        exit 3
    }
}

# 4. Check Windows Update Service (wuauserv) State
$WUService = Get-Service -Name "wuauserv"
if ($WUService.Status -eq "Stopped" -and $WUService.StartType -eq "Disabled") {
    Write-MSPLog "ERROR: Windows Update service is disabled. Policy cannot be reliably applied."
    exit 4
}

try {
    foreach ($Policy in $RegistryPolicies) {
        if ($Action -eq "Apply") {
            if (!(Test-Path $Policy.Path)) {
                New-Item -Path $Policy.Path -Force | Out-Null
                Write-MSPLog "Created registry path: $($Policy.Path)"
            }
            Set-ItemProperty -Path $Policy.Path -Name $Policy.Name -Value $Policy.Value -Type $Policy.Type -Force
            Write-MSPLog "APPLIED: $($Policy.Name) set to $($Policy.Value)"
        }
        else {
            if (Get-ItemProperty -Path $Policy.Path -Name $Policy.Name -ErrorAction SilentlyContinue) {
                Remove-ItemProperty -Path $Policy.Path -Name $Policy.Name -Force
                Write-MSPLog "REMOVED: $($Policy.Name) restriction."
            }
        }
    }

    # Force Registry/Policy Refresh
    Write-MSPLog "Triggering local policy refresh..."
    Start-Process -FilePath "gpupdate.exe" -ArgumentList "/force" -NoNewWindow -Wait
    
    Write-MSPLog "COMPLETED: Windows Update UI restrictions configured successfully."
    exit 0
}
catch {
    Write-MSPLog "CRITICAL ERROR: $($_.Exception.Message)"
    exit 1
}
finally {
    Write-MSPLog "Script Execution Finished."
}