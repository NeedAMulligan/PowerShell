<#
.SYNOPSIS
    Installs and updates essential administrative PowerShell modules for Windows Server environments.

.DESCRIPTION
    This script automates the setup of an admin workstation/server. It configures TLS 1.2, 
    trusts PSGallery, installs NuGet, and ensures the latest versions of Microsoft 365 
    and Windows Update modules are installed. Logs are saved to C:\temp.

.EXAMPLE
    .\Install-AdminModules.ps1
#>

# ---------------------------------------------------------------------------
# VARIABLES
# ---------------------------------------------------------------------------
$ModulesToInstall = @(
    "MicrosoftTeams",
    "NuGet",
    "PackageManagement",
    "PowerShellGet",
    "Microsoft.Online.SharePoint.PowerShell",
    "Microsoft.WinGet.Client",
    "Microsoft.Graph",
    "ExchangeOnlineManagement",
    "PSWindowsUpdate"
)

$LogDir     = "C:\temp"
$Timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile    = Join-Path $LogDir "Install-AdminModules_$Timestamp.log"
$ErrorFound = $false

# ---------------------------------------------------------------------------
# FUNCTIONS
# ---------------------------------------------------------------------------
function Write-Log {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error")]
        [string]$Level = "Info"
    )
    $LogEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$($Level.ToUpper())] $Message"
    
    # Write to console for interactivity
    switch ($Level) {
        "Info"    { Write-Host $LogEntry -ForegroundColor Cyan }
        "Warning" { Write-Host $LogEntry -ForegroundColor Yellow }
        "Error"   { Write-Host $LogEntry -ForegroundColor Red }
    }
    
    # Write to file
    $LogEntry | Out-File -FilePath $LogFile -Append
}

# ---------------------------------------------------------------------------
# EXECUTION LOGIC
# ---------------------------------------------------------------------------

# 1. Check for Admin Privileges
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "This script must be run as Administrator."
    exit 1
}

# 2. Setup Logging Directory
if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

Write-Log "Starting Module Installation Script."
Write-Log "Logging to: $LogFile"

# 3. Environment Hardening & Requirements
try {
    Write-Log "Enforcing TLS 1.2 for secure gallery connections..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    Write-Log "Setting PSGallery to Trusted..."
    Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted -ErrorAction Stop

    Write-Log "Installing/Updating NuGet Provider..."
    Install-PackageProvider -Name "NuGet" -MinimumVersion 2.8.5.201 -Force -ErrorAction Stop
}
catch {
    Write-Log "Critical Environment Setup Failed: $_" -Level Error
    exit 2
}

# 4. Install Windows Features (RSAT-AD)
try {
    Write-Log "Ensuring RSAT-AD-PowerShell is installed..."
    $Feature = Get-WindowsFeature -Name RSAT-AD-PowerShell
    if (-not $Feature.Installed) {
        Install-WindowsFeature -Name RSAT-AD-PowerShell -IncludeAllSubFeature -ErrorAction Stop
        Write-Log "Successfully installed RSAT-AD-PowerShell."
    } else {
        Write-Log "RSAT-AD-PowerShell is already present."
    }
}
catch {
    Write-Log "Failed to install RSAT-AD-PowerShell: $_" -Level Error
    $ErrorFound = $true
}

# 5. Process Modules
foreach ($ModuleName in $ModulesToInstall) {
    try {
        $InstalledModule = Get-Module -ListAvailable -Name $ModuleName -ErrorAction SilentlyContinue
        
        if ($InstalledModule) {
            Write-Log "Updating module: $ModuleName..."
            Update-Module -Name $ModuleName -Force -ErrorAction Stop
            Write-Log "$ModuleName updated successfully."
        }
        else {
            Write-Log "Installing module: $ModuleName..."
            Install-Module -Name $ModuleName -Scope AllUsers -Force -AllowClobber -ErrorAction Stop
            Write-Log "$ModuleName installed successfully."
        }
    }
    catch {
        Write-Log "Failed to process module '$ModuleName': $_" -Level Error
        $ErrorFound = $true
    }
}

# 6. Final Summary
Write-Log "----------------------------------------------------"
if ($ErrorFound) {
    Write-Log "Script completed with errors. Please review the log file." -Level Warning
    exit 3
} else {
    Write-Log "All tasks completed successfully. ✨"
    exit 0
}
