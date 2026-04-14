<#
.SYNOPSIS
    Sets Dell Power Manager charging mode to 'Adaptive'.

.DESCRIPTION
    1. Verifies the system is a Dell machine using CIM.
    2. Ensures the script is running with Administrative privileges.
    3. Checks for/Installs 'DellBIOSProvider' (formerly DellCommandPowerShellProvider).
    4. Sets 'PrimaryBattChargeCfg' or 'PrimaryBatteryChargeConfiguration' to 'Adaptive'.
    5. Logs all actions to C:\temp with timestamping.

.PARAMETER Silent
    The script is designed to run silently by default. Output is directed to the log file.

.EXAMPLE
    .\Set-DellAdaptivePower.ps1
#>

# ---------------------------------------------------------
# VARIABLES
# ---------------------------------------------------------
$LogPath      = "C:\temp"
$ScriptName   = "Set-DellAdaptivePower"
$Timestamp    = Get-Date -Format "yyyyMMdd_HHmmss"
$FullLogPath  = Join-Path $LogPath "$($ScriptName)_$($Timestamp).log"

$TargetMode   = "Adaptive"
$ModuleName   = "DellBIOSProvider"

# ---------------------------------------------------------
# FUNCTIONS
# ---------------------------------------------------------

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )
    $LogTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$LogTimestamp] [$Level] - $Message"
    
    if (-not (Test-Path $LogPath)) { 
        New-Item -Path $LogPath -ItemType Directory -Force | Out-Null 
    }
    $LogEntry | Out-File -FilePath $FullLogPath -Append
}

function Test-IsAdmin {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Install-DellProvider {
    Write-Log "Checking for Dell Command PowerShell Provider ($ModuleName)..."
    if (-not (Get-Module -ListAvailable -Name $ModuleName)) {
        try {
            Write-Log "Provider not found. Attempting installation from PSGallery..."
            
            # Ensure TLS 1.2 for Gallery downloads
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            
            Set-Service -Name "wuauserv" -StartupType Manual -ErrorAction SilentlyContinue
            
            Write-Log "Installing NuGet Provider..."
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false -ErrorAction Stop
            
            Write-Log "Installing Module ${ModuleName}..."
            Install-Module -Name $ModuleName -Force -AllowClobber -Confirm:$false -ErrorAction Stop
            
            Write-Log "Successfully installed ${ModuleName}."
        }
        catch {
            # FIX: Using ${ModuleName} to avoid drive-reference parser errors
            Write-Log "FAILED to install ${ModuleName}: $($_.Exception.Message)" "ERROR"
            exit 3
        }
    }
    else {
        Write-Log "Dell Provider already present."
    }
}

# ---------------------------------------------------------
# MAIN EXECUTION
# ---------------------------------------------------------

try {
    # 1. Admin Check
    if (-not (Test-IsAdmin)) {
        Write-Log "Script must be run as Administrator." "ERROR"
        Write-Error "Administrative privileges required."
        exit 2
    }

    # 2. Hardware Check (Using Get-CimInstance for better performance/reliability)
    $Chassis = Get-CimInstance -ClassName Win32_ComputerSystem
    if ($Chassis.Manufacturer -notmatch "Dell") {
        Write-Log "Non-Dell system detected ($($Chassis.Manufacturer)). Exiting." "WARN"
        exit 1
    }

    # 3. Dependency Handling
    Install-DellProvider
    
    # Import the provider to create the DellSmbios: drive
    if (-not (Get-PSDrive -Name "DellSmbios" -ErrorAction SilentlyContinue)) {
        Write-Log "Importing $ModuleName..."
        Import-Module $ModuleName -ErrorAction Stop
    }

    # 4. Configuration Logic
    # Attribute names vary across Dell BIOS generations
    $PossiblePaths = @(
        "DellSmbios:\PowerManagement\PrimaryBattChargeCfg",
        "DellSmbios:\PowerManagement\PrimaryBatteryChargeConfiguration"
    )

    $Applied = $false
    foreach ($Path in $PossiblePaths) {
        if (Test-Path $Path) {
            $CurrentValue = (Get-Item $Path).CurrentValue
            
            if ($CurrentValue -eq $TargetMode) {
                Write-Log "Setting is already set to $TargetMode at $Path. No change needed."
                $Applied = $true
                break
            }

            Write-Log "Updating $Path from $CurrentValue to $TargetMode..."
            Set-Item -Path $Path -Value $TargetMode -ErrorAction Stop
            Write-Log "Successfully updated to $TargetMode."
            $Applied = $true
            break
        }
    }

    if (-not $Applied) {
        throw "Could not find a valid Power Management BIOS attribute for battery charging. Ensure Dell Command | Configure is compatible with this model."
    }

    Write-Log "Script completed successfully."
    exit 0

}
catch {
    Write-Log "CRITICAL ERROR: $($_.Exception.Message)" "ERROR"
    exit 4
}