<#
.SYNOPSIS
    Checks for the installation of Dell Command | Update (DCU), removes conflicting software, installs the Universal version if needed, and configures settings silently.

.DESCRIPTION
    This script performs the following actions:
    1. Checks if Dell Command | Update is installed.
    2. If NOT installed:
       a. Removes common conflicting Dell Update programs silently.
       b. Downloads and installs the DCU Universal application silently using the DUP file link provided (Driver ID C8JXV).
    3. If DCU is installed (either initially or after installation), it configures the following registry settings:
       - Update Action: Set to 'Notify Only' (corresponds to 'Downloads and notifies').
       - Advanced Driver Restore (ADR): Enabled.

.NOTES
    - Requires Administrative privileges (Elevated PowerShell) for registry modification, installation, and uninstallation.
    - Script is designed to be completely silent (no console output).
    - Log file is written to C:\Temp with a dynamic name.

.EXIT CODES
    0: Success. All configuration steps completed successfully.
    1: DCU installation/verification failed. DCU is not installed, and automatic installation attempt failed. Configuration skipped.
    2: Configuration Failed. Failed to set one or more required registry keys (e.g., permissions issue or missing key).
#>

[CmdletBinding()]
param()

#region Script Configuration

# LOGGING SETUP
$LogPath = "C:\Temp"
$LogFile = "DellCommandUpdate_Config_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$FullLogPath = Join-Path -Path $LogPath -ChildPath $LogFile
$ExitCode = 0

# INSTALLER VARIABLES - Updated with the direct DUP link for Dell Command Update v5.5.0 (C8JXV)
$DCUDownloadURL = "https://dl.dell.com/FOLDER10646142M/1/Dell-Command-Update-Application_C8JXV_WIN_5.5.0_A00.EXE"
$DCUInstallerName = "DCUUniversal.exe"
$LocalInstallerPath = Join-Path -Path $LogPath -ChildPath $DCUInstallerName

# COMMON DCU CLI PATHS (Used to verify installation)
$DCUPath64 = "$env:ProgramFiles\Dell\CommandUpdate\dcu-cli.exe"
$DCUPath32 = "$env:ProgramFiles(x86)\Dell\CommandUpdate\dcu-cli.exe"

# COMMON DCU REGISTRY PATH (Used for silent setting configuration)
$DCUKeyPath = "HKLM:\SOFTWARE\Dell\UpdateService\Settings"

# CONFIGURATION VALUES (Registry DWORD)
# 1. UpdateSettings\WhenUpdatesAreFound: 1 = Notify Only (Downloads and notifies)
$UpdateActionKey = "UpdateSettings\WhenUpdatesAreFound"
$UpdateActionValue = 1

# 2. AdvancedDriverRestore\FeatureEnabled: 1 = Enabled
$ADRKey = "AdvancedDriverRestore\FeatureEnabled"
$ADRValue = 1

#endregion

#region Logging Function
function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [Parameter(Mandatory=$false)][int]$Code = 0
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp - $Message" | Out-File -FilePath $FullLogPath -Append -Force
    if ($Code -ne 0) {
        $script:ExitCode = $Code
        "$Timestamp - Exiting with code $Code." | Out-File -FilePath $FullLogPath -Append -Force
        exit $Code
    }
}
#endregion

#region Removal and Installation Functions

function Remove-OldDellUpdate {
    Write-Log -Message "STATUS: Searching for and removing potentially conflicting Dell Update programs..."

    # Common names for Dell Update software to look for in the Uninstall registry key
    $ProgramsToUninstallRegex = "(Dell Command \| Update)|(Dell Update)|(Dell Update Universal Application)"
    $UninstallKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    
    $UninstallSuccess = $true

    foreach ($Key in $UninstallKeys) {
        if (Test-Path $Key) {
            # Find matching software entries
            $Software = Get-ChildItem -Path $Key -ErrorAction SilentlyContinue |
                        Get-ItemProperty -ErrorAction SilentlyContinue |
                        Where-Object { $_.DisplayName -match $ProgramsToUninstallRegex -and $_.UninstallString }

            foreach ($Program in $Software) {
                $DisplayName = $Program.DisplayName
                $UninstallCommand = $Program.UninstallString
                
                # Check for msiexec commands and adjust arguments
                if ($UninstallCommand -match 'msiexec\.exe') {
                    # For MSI, ensure /qn (quiet, no UI) is used
                    $CommandArgs = "$UninstallCommand /qn"
                } else {
                    # Assume DUP or standard installer, use /s for silent
                    $CommandArgs = "$UninstallCommand /s /qn"
                }

                Write-Log -Message "ATTEMPT: Found '$DisplayName'. Executing uninstall command: $CommandArgs"

                try {
                    # Execute the uninstall command silently using PowerShell to handle the start-process call
                    $Process = Start-Process powershell -ArgumentList "-WindowStyle Hidden -Command & {$CommandArgs}" -NoNewWindow -Wait -PassThru -ErrorAction Stop
                    
                    if ($Process.ExitCode -eq 0 -or $Process.ExitCode -eq 1641 -or $Process.ExitCode -eq 3010) {
                        # Exit code 0, 1641 (success/reboot needed), 3010 (success/reboot needed) are successful uninstalls
                        Write-Log -Message "SUCCESS: '$DisplayName' removed successfully (Exit Code $($Process.ExitCode))."
                    } else {
                        Write-Log -Message "WARNING: '$DisplayName' uninstall command executed with non-successful exit code: $($Process.ExitCode)."
                        $UninstallSuccess = $false
                    }
                } catch {
                    Write-Log -Message "ERROR: Failed to execute uninstall command for '$DisplayName'. $($_.Exception.Message)"
                    $UninstallSuccess = $false
                }
            }
        }
    }
    return $UninstallSuccess
}

function Install-DCUUniversal {
    Write-Log -Message "STATUS: Starting silent download and installation of Dell Command Update Universal."

    # Download the installer
    try {
        Write-Log -Message "ATTEMPT: Downloading DCU installer from $DCUDownloadURL to $LocalInstallerPath"
        Invoke-WebRequest -Uri $DCUDownloadURL -OutFile $LocalInstallerPath -UseBasicParsing -ErrorAction Stop
        Write-Log -Message "SUCCESS: Download complete."
    } catch {
        Write-Log -Message "ERROR: Failed to download DCU installer from $DCUDownloadURL. $($_.Exception.Message)"
        return $false
    }

    # Install the program silently
    try {
        Write-Log -Message "ATTEMPT: Starting silent installation of DCU ($LocalInstallerPath /s)"
        
        # /s is the universal switch for Dell Update Packages (DUP)
        $Process = Start-Process -FilePath $LocalInstallerPath -ArgumentList "/s" -Wait -PassThru -ErrorAction Stop
        
        if ($Process.ExitCode -eq 0 -or $Process.ExitCode -eq 1641 -or $Process.ExitCode -eq 3010) {
            Write-Log -Message "SUCCESS: DCU installation completed successfully (Exit Code $($Process.ExitCode)). Waiting 10 seconds for service initialization."
            Start-Sleep -Seconds 10 # Wait for services and registry keys to populate
            return $true
        } else {
            Write-Log -Message "ERROR: DCU installation failed with non-zero exit code: $($Process.ExitCode)."
            return $false
        }
    } catch {
        Write-Log -Message "ERROR: Failed to start DCU installer process. $($_.Exception.Message)"
        return $false
    } finally {
        # Clean up the downloaded installer file
        if (Test-Path -Path $LocalInstallerPath) {
             Remove-Item -Path $LocalInstallerPath -Force -ErrorAction SilentlyContinue
             Write-Log -Message "INFO: Cleaned up installer file at $LocalInstallerPath."
        }
    }
}
#endregion

#region Pre-Checks and Setup

# 1. Ensure the log path exists
if (-not (Test-Path -Path $LogPath)) {
    try {
        New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
    } catch {
        # Cannot log if folder creation fails, so we just exit
        exit 2
    }
}
Write-Log -Message "Log file initialized."

# 2. Check if DCU is installed and decide action
$DCUInstalled = $false
$DCUExePath = $null

if (Test-Path -Path $DCUPath64) {
    $DCUInstalled = $true
    $DCUExePath = $DCUPath64
    Write-Log -Message "INFO: Dell Command Update 64-bit application found at: $DCUExePath. Skipping installation steps."
} elseif (Test-Path -Path $DCUPath32) {
    $DCUInstalled = $true
    $DCUExePath = $DCUPath32
    Write-Log -Message "INFO: Dell Command Update 32-bit application found at: $DCUExePath. Skipping installation steps."
} else {
    Write-Log -Message "WARNING: Dell Command Update was not found. Attempting removal of old versions and silent installation."
    
    # NEW LOGIC: Remove and Install
    $RemovalSuccessful = Remove-OldDellUpdate
    
    if ($RemovalSuccessful) {
        $InstallSuccessful = Install-DCUUniversal
        if ($InstallSuccessful) {
            Write-Log -Message "STATUS: DCU installation attempted. Re-checking for installation path."
            # Re-check paths after install
            if (Test-Path -Path $DCUPath64) {
                $DCUInstalled = $true
                $DCUExePath = $DCUPath64
            } elseif (Test-Path -Path $DCUPath32) {
                $DCUInstalled = $true
                $DCUExePath = $DCUPath32
            }
        }
    }

    if (-not $DCUInstalled) {
        Write-Log -Message "FATAL: Dell Command Update could not be installed or verified after installation. Configuration aborted." -Code 1
    }
}

# 3. Check for the registry path (must exist to write settings)
if ($DCUInstalled -and (-not (Test-Path -Path $DCUKeyPath))) {
    Write-Log -Message "ERROR: DCU application path found, but required registry key ($DCUKeyPath) is missing. Cannot configure." -Code 2
}

#endregion

#region Configuration Logic
if ($DCUInstalled -and (Test-Path -Path $DCUKeyPath)) {
    Write-Log -Message "STATUS: Starting Dell Command Update configuration..."
    $ConfigSuccess = $true

    # 1. Configure Update Action: Notify Only (Downloads and notifies)
    try {
        $FullUpdateActionKey = Join-Path -Path $DCUKeyPath -ChildPath $UpdateActionKey
        Set-ItemProperty -Path $FullUpdateActionKey -Name "(Default)" -Value $UpdateActionValue -Type DWord -Force
        Write-Log -Message "SUCCESS: Set Update Action to '$UpdateActionValue' (Notify Only)."
    } catch {
        $ConfigSuccess = $false
        Write-Log -Message "ERROR: Failed to set Update Action registry key. $($_.Exception.Message)"
    }

    # 2. Configure Advanced Driver Restore (ADR): Enable
    try {
        $FullADRKey = Join-Path -Path $DCUKeyPath -ChildPath $ADRKey
        Set-ItemProperty -Path $FullADRKey -Name "(Default)" -Value $ADRValue -Type DWord -Force
        Write-Log -Message "SUCCESS: Enabled Advanced Driver Restore (ADR)."
    } catch {
        $ConfigSuccess = $false
        Write-Log -Message "ERROR: Failed to set Advanced Driver Restore (ADR) registry key. $($_.Exception.Message)"
    }

    if (-not $ConfigSuccess) {
        Write-Log -Message "FAILURE: One or more configuration settings failed to apply." -Code 2
    } else {
        Write-Log -Message "STATUS: Configuration complete."
    }
}
#endregion

# If successful, exit with code 0 (This is the default if no errors occurred)
Write-Log -Message "Script finished successfully." -Code 0