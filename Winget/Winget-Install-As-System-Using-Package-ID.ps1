# =============================================
# Script: Install-WinGetPackage-AsSystem.ps1
# Description:
# This script installs a specified WinGet package while running under the SYSTEM context.
# It includes logging, idempotency checks, error handling, and environment validation.
# The package ID is passed as a parameter for reuse across deployments.
# =============================================

<#
.SYNOPSIS
Installs a WinGet package as SYSTEM.

.DESCRIPTION
This script installs any WinGet package by Package ID using SYSTEM context.
Includes pre-checks, logging, idempotency validation, and robust error handling.

.PARAMETER PackageId
The WinGet package ID to install (e.g., EclipseAdoptium.Temurin.25.JDK)

.EXAMPLE
.\Install-WinGetPackage-AsSystem.ps1 -PackageId "EclipseAdoptium.Temurin.25.JDK"

#>

param (
    [Parameter(Mandatory = $true)]
    [string]$PackageId
)

# Exit Codes:
# 0    = Success / Already Installed
# 1001 = WinGet not found
# 1002 = Pre-check failure
# 1003 = Installation failure

# =========================
# Configuration
# =========================
$LogDirectory = "C:\temp"
$TimeStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$SafePackageName = $PackageId -replace '[^a-zA-Z0-9]', '_'
$LogFile = Join-Path $LogDirectory "Install_${SafePackageName}_$TimeStamp.log"

# =========================
# Logging Function
# =========================
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )

    $Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Entry = "$Time [$Level] $Message"

    Write-Output $Entry
    Add-Content -Path $LogFile -Value $Entry
}

# =========================
# Pre-flight Checks
# =========================

# Ensure log directory exists
if (!(Test-Path $LogDirectory)) {
    New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
}

Write-Log "Starting WinGet installation script for package: $PackageId"

# Locate WinGet
$WinGetPaths = @(
    "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*\winget.exe",
    "$env:SystemRoot\System32\winget.exe"
)

$WinGetExe = $null

foreach ($Path in $WinGetPaths) {
    $Resolved = Get-ChildItem -Path $Path -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($Resolved) {
        $WinGetExe = $Resolved.FullName
        break
    }
}

if (-not $WinGetExe) {
    Write-Log "WinGet executable not found." "ERROR"
    exit 1001
}

Write-Log "Using WinGet at: $WinGetExe"

# Initialize sources (required in SYSTEM context)
Write-Log "Ensuring WinGet sources are available..."
& $WinGetExe source update | Out-Null

# =========================
# Idempotency Check
# =========================
Write-Log "Checking if package is already installed..."

$CheckArgs = @("list", "--id", $PackageId, "--exact")
$Installed = & $WinGetExe $CheckArgs 2>$null

if ($Installed -match $PackageId) {
    Write-Log "Package already installed. Exiting."
    exit 0
}

# =========================
# Installation
# =========================
Write-Log "Starting installation of $PackageId..."

try {
    $WingetArgs = @(
        "install",
        "--id", $PackageId,
        "--exact",
        "--silent",
        "--accept-source-agreements",
        "--accept-package-agreements",
        "--disable-interactivity"
    )

    Write-Log "Executing: winget $($WingetArgs -join ' ')"

    & $WinGetExe $WingetArgs | Out-File -FilePath $LogFile -Append

    if ($LASTEXITCODE -eq 0) {
        Write-Log "Installation completed successfully."

        # Reboot check
        if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") {
            Write-Log "WARNING: System reboot may be required." "WARN"
        }

        exit 0
    }
    else {
        Write-Log "WinGet install failed with Exit Code: $LASTEXITCODE" "ERROR"
        exit 1003
    }
}
catch {
    Write-Log "CRITICAL ERROR: $($_.Exception.Message)" "ERROR"
    exit 1003
}
