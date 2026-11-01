<#
.SYNOPSIS
    Configures Dell BIOS AC Power Recovery (WakeOnAc) to Enabled.
.DESCRIPTION
    Checks/installs DellBIOSProvider module, logs actions dynamically to C:\temp,
    prunes old logs, and sets WakeOnAc to Enabled with robust try-catch error handling.
#>

[CmdletBinding()]
param()

# --- Configuration Variables ---
$ModuleName    = "DellBIOSProvider"
$RegistryPath  = "DellSmbios:\PowerManagement"
$AttributeName = "WakeOnAc"
$DesiredValue  = "Enabled"
$LogDir        = "C:\temp"
$Timestamp     = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile       = Join-Path $LogDir "Set-Dell-BIOS-AC-Power-Recovery-On_$Timestamp.log"

# --- Logging & Pruning Function ---
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $LogEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    Add-Content -Path $LogFile -Value $LogEntry
    if ($Level -eq "ERROR") {
        Write-Error $Message
    } else {
        Write-Verbose $Message
    }
}

# Ensure log directory exists
if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

# Prune log files older than 7 days
Get-ChildItem -Path $LogDir -Filter "Set-Dell-BIOS-AC-Power-Recovery-On_*.log" | 
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } | 
    Remove-Item -Force -ErrorAction SilentlyContinue

Write-Log "Starting Dell BIOS AC Power Recovery configuration script."

try {
    # --- Prerequisite Module Check ---
    Write-Log "Checking for module: $ModuleName..."
    $Module = Get-Module -ListAvailable -Name $ModuleName
    if (-not $Module) {
        Write-Log "Module $ModuleName not found. Installing..."
        Install-Module -Name $ModuleName -Force -Scope AllUsers -ErrorAction Stop
        Write-Log "Module $ModuleName installed successfully."
    } else {
        Write-Log "Module $ModuleName is already installed."
    }

    # --- Import Module ---
    Write-Log "Importing module $ModuleName..."
    Import-Module -Name $ModuleName -ErrorAction Stop

    # --- Set Location & Attribute ---
    if (-not (Test-Path $RegistryPath)) {
        Write-Log "Path $RegistryPath does not exist on this system." -Level "ERROR"
        throw "BIOS provider path not found: $RegistryPath"
    }

    Set-Location -Path $RegistryPath -ErrorAction Stop
    Write-Log "Working directory set to $RegistryPath."

    if (-not (Test-Path $AttributeName)) {
        Write-Log "Attribute $AttributeName does not exist under $RegistryPath." -Level "ERROR"
        throw "BIOS attribute not found: $AttributeName"
    }

    Write-Log "Setting $AttributeName to $DesiredValue..."
    Set-Item -Path ".\$AttributeName" -Value $DesiredValue -ErrorAction Stop

    $CurrentVal = (Get-Item -Path ".\$AttributeName").CurrentValue
    Write-Log "Verification: $AttributeName current value is now $CurrentVal."

}
catch {
    Write-Log "An error occurred: $_" -Level "ERROR"
    throw $_
}
finally {
    Write-Log "Script execution completed."
}
