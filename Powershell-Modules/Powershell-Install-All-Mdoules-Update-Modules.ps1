<#
.SYNOPSIS
    Comprehensive Admin Environment Setup for Windows Server (2019/2022).

.DESCRIPTION
    Standardizes a local server by:
    1. Enforcing TLS 1.2 and Trusting PSGallery.
    2. Installing/Updating NuGet and PowerShellGet.
    3. Installing M365 Modules (Teams, SharePoint, Exchange, Full Graph).
    4. Installing Windows Update and WinGet modules.
    5. Bootstrapping the WinGet engine (winget.exe) for Server OS.
    6. Logging all actions to C:\temp.

.NOTES
    Configured for Interactive Output with background logging.
#>

# ---------------------------------------------------------------------------
# 1. CONFIGURABLE VARIABLES
# ---------------------------------------------------------------------------
$ModulesToInstall = @(
    "NuGet",
    "PowerShellGet",
    "MicrosoftTeams",
    "Microsoft.Online.SharePoint.PowerShell",
    "ExchangeOnlineManagement",
    "Microsoft.Graph",
    "PSWindowsUpdate",
    "Microsoft.WinGet.Client"
)

$LogDir     = "C:\temp"
$Timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile    = Join-Path $LogDir "ServerAdminSetup_$Timestamp.log"
$ErrorFound = $false

# ---------------------------------------------------------------------------
# 2. HELPER FUNCTIONS
# ---------------------------------------------------------------------------
function Write-Log {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error")]
        [string]$Level = "Info"
    )
    $LogEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$($Level.ToUpper())] $Message"
    
    # Interactive UI Output
    switch ($Level) {
        "Info"    { Write-Host $LogEntry -ForegroundColor Cyan }
        "Warning" { Write-Host $LogEntry -ForegroundColor Yellow }
        "Error"   { Write-Host $LogEntry -ForegroundColor Red }
    }
    
    # Persistent Logging
    $LogEntry | Out-File -FilePath $LogFile -Append
}

# ---------------------------------------------------------------------------
# 3. PRE-EXECUTION CHECKS & ENVIRONMENT SETUP
# ---------------------------------------------------------------------------

# Ensure Admin privileges
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "CRITICAL: This script must be run as Administrator."
    exit 1
}

# Ensure Log Directory exists
if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }

Write-Log "Initializing Server Admin Module Deployment..."
Write-Log "Log file initialized at: $LogFile"

try {
    Write-Log "Enforcing TLS 1.2 for secure connections..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    Write-Log "Setting PSGallery to Trusted..."
    Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted -ErrorAction Stop

    Write-Log "Ensuring NuGet Provider is current..."
    Install-PackageProvider -Name "NuGet" -MinimumVersion 2.8.5.201 -Force -ErrorAction Stop
}
catch {
    Write-Log "Failed to initialize environment: $_" -Level Error
    exit 2
}

# ---------------------------------------------------------------------------
# 4. WINDOWS FEATURE INSTALLATION (RSAT)
# ---------------------------------------------------------------------------
try {
    Write-Log "Checking for RSAT Active Directory PowerShell modules..."
    $Feature = Get-WindowsFeature -Name RSAT-AD-PowerShell
    if (-not $Feature.Installed) {
        Write-Log "Installing RSAT-AD-PowerShell..."
        Install-WindowsFeature -Name RSAT-AD-PowerShell -IncludeAllSubFeature -ErrorAction Stop
    } else {
        Write-Log "RSAT-AD-PowerShell is already installed."
    }
}
catch {
    Write-Log "Failed to install Windows Feature: $_" -Level Error
    $ErrorFound = $true
}

# ---------------------------------------------------------------------------
# 5. MODULE INSTALLATION & WINGET BOOTSTRAPPING
# ---------------------------------------------------------------------------
foreach ($ModuleName in $ModulesToInstall) {
    try {
        $ModuleCheck = Get-Module -ListAvailable -Name $ModuleName -ErrorAction SilentlyContinue
        
        if ($ModuleCheck) {
            Write-Log "[$ModuleName] Updating existing module..."
            Update-Module -Name $ModuleName -Force -AcceptLicense -ErrorAction Stop
            Write-Log "[$ModuleName] Update complete."
        }
        else {
            Write-Log "[$ModuleName] Installing new module..."
            # -AcceptLicense is required for Graph/Teams in newer versions
            Install-Module -Name $ModuleName -Scope AllUsers -Force -AllowClobber -AcceptLicense -ErrorAction Stop
            Write-Log "[$ModuleName] Installation complete."
        }

        # Special logic for WinGet engine on Server OS
        if ($ModuleName -eq "Microsoft.WinGet.Client") {
            Write-Log "Attempting to bootstrap WinGet Engine (winget.exe) for Server..."
            # This cmdlet downloads required dependencies for Server environments
            Repair-WinGetPackageManager -Confirm:$false -ErrorAction SilentlyContinue
            Write-Log "WinGet Engine bootstrap process finished."
        }
    }
    catch {
        Write-Log "FAILED to process module '$ModuleName': $_" -Level Error
        $ErrorFound = $true
    }
}

# ---------------------------------------------------------------------------
# 6. FINALIZATION
# ---------------------------------------------------------------------------
Write-Log "----------------------------------------------------------------"
if ($ErrorFound) {
    Write-Log "Script completed with one or more errors. Check the log for details." -Level Warning
    exit 3
} else {
    Write-Log "SUCCESS: All modules and features are ready for use."
    exit 0
}
