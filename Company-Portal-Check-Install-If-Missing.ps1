<#
.SYNOPSIS
    Universal Company Portal Installer for Corporate and Personal Windows devices.
.DESCRIPTION
    Optimized for Intune Platform Scripts. Handles the 'SYSTEM' context 
    initialization required for WinGet to function on varied device types.
.NOTES
    Intune Settings: 
    - Run as 64-bit: Yes
    - Run as SYSTEM: Yes (Recommended for Corporate) OR User (if BYOD apps are user-based).
#>

# --------------------------------------------------------------------------
# VARIABLES
# --------------------------------------------------------------------------
$PackageId    = "9WZDNCRFJ3PZ"
$LogDir       = "C:\temp"
$LogPath      = "$LogDir\CP_Install_$(Get-Date -Format 'yyyyMMdd_HHmm').log"

# --------------------------------------------------------------------------
# EXIT CODES
# 0 = Success | 1 = General Fail | 3 = WinGet Missing | 5 = Access Denied
# --------------------------------------------------------------------------

if (!(Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
Start-Transcript -Path $LogPath

function Write-Log { param($Msg) Write-Output "$(Get-Date -Format 'HH:mm:ss') - $Msg" }

try {
    Write-Log "Starting Universal Deployment Check..."

    # 1. Check if App is already there
    $App = Get-AppxPackage -AllUsers | Where-Object {$_.Name -like "*CompanyPortal*"}
    if ($App) {
        Write-Log "Company Portal already installed. Exiting."
        exit 0
    }

    # 2. Bypass WinGet 'Source' issues (Crucial for Personal/BYOD machines)
    # This forces the SYSTEM/Local account to accept the MS Store source terms
    Write-Log "Refreshing WinGet Source Agreements..."
    & winget source reset --force
    & winget source update

    # 3. Attempt Silent Install
    Write-Log "Executing Install for ID: $PackageId"
    $Install = Start-Process -FilePath "winget.exe" -ArgumentList "install --id $PackageId --source msstore --accept-package-agreements --accept-source-agreements --silent" -Wait -PassThru -NoNewWindow

    if ($Install.ExitCode -eq 0) {
        Write-Log "Installation Successful."
        exit 0
    } else {
        Write-Log "Install failed with code: $($Install.ExitCode)"
        exit 1
    }
}
catch {
    Write-Log "Error: $($_.Exception.Message)"
    exit 1
}
finally {
    Stop-Transcript
}