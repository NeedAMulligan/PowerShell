<#
.SYNOPSIS
    Sets Dell Power Manager charging mode to 'Adaptive'.

.DESCRIPTION
    1. Verifies the system is a Dell machine.
    2. Ensures the script is running with Administrative privileges.
    3. Checks for/Installs 'DellCommandPowerShellProvider'.
    4. Sets 'PrimaryBattChargeCfg' or 'PrimaryBatteryChargeConfiguration' to 'Adaptive'.
    5. Logs all actions to C:\temp.

.PARAMETER Silent
    The script is designed to run silently by default based on user requirements.

.EXAMPLE
    .\Set-DellAdaptivePower.ps1
#>

# ---------------------------------------------------------
# VARIABLES
# ---------------------------------------------------------
$LogPath      = "C:\temp"
$LogFileName  = "Set-DellAdaptivePower_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$FullLogPath  = Join-Path $LogPath $LogFileName
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
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] [$Level] - $Message"
    
    if (-not (Test-Path $LogPath)) { New-Item -Path $LogPath -ItemType Directory -Force | Out-Null }
    $LogEntry | Out-File -FilePath $FullLogPath -Append
}

function Test-IsAdmin {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Install-DellProvider {
    Write-Log "Checking for Dell Command PowerShell Provider..."
    if (-not (Get-Module -ListAvailable -Name $ModuleName)) {
        try {
            Write-Log "Provider not found. Attempting installation from PSGallery..."
            Set-Service -Name "wuauserv" -StartupType Manual -ErrorAction SilentlyContinue
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false -ErrorAction Stop
            Install-Module -Name $ModuleName -Force -AllowClobber -Confirm:$false -ErrorAction Stop
            Write-Log "Successfully installed $ModuleName."
        }
        catch {
            Write-Log "FAILED to install $ModuleName: $($_.Exception.Message)" "ERROR"
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
        exit 2
    }

    # 2. Hardware Check
    $Chassis = Get-WmiObject -Class Win32_ComputerSystem
    if ($Chassis.Manufacturer -notmatch "Dell") {
        Write-Log "Non-Dell system detected ($($Chassis.Manufacturer)). Exiting." "WARN"
        exit 1
    }

    # 3. Dependency Handling
    Install-DellProvider
    
    # Import the provider to create the DellSmbios: drive
    if (-not (Get-PSDrive -Name "DellSmbios" -ErrorAction SilentlyContinue)) {
        Import-Module $ModuleName -ErrorAction Stop
    }

    # 4. Configuration Logic
    # Note: Attribute name varies slightly between BIOS versions (PrimaryBattChargeCfg vs PrimaryBatteryChargeConfiguration)
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
        throw "Could not find a valid Power Management BIOS attribute for battery charging."
    }

    Write-Log "Script completed successfully."
    exit 0

}
catch {
    Write-Log "CRITICAL ERROR: $($_.Exception.Message)" "ERROR"
    exit 4
}