<#
.SYNOPSIS
    Optimized Server Module Deployment for Endpoint Central (Running as SYSTEM)
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
    
    # Standard output stream for Endpoint Central logging
    Write-Output $LogEntry
    
    # File logging
    $LogEntry | Out-File -FilePath $LogFile -Append -Encoding utf8
}

# ---------------------------------------------------------------------------
# 3. PRE-EXECUTION CHECKS & ENVIRONMENT SETUP
# ---------------------------------------------------------------------------

if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }

Write-Log "Initializing Server Admin Module Deployment..."

try {
    Write-Log "Enforcing TLS 1.2..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    Write-Log "Ensuring NuGet Provider is current..."
    Install-PackageProvider -Name "NuGet" -MinimumVersion 2.8.5.201 -Force -Scope AllUsers -ErrorAction Stop

    Write-Log "Ensuring PSGallery repository is trusted..."
    try {
        Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted -ErrorAction Stop
    } catch {
        # Fallback if PSGallery is missing in SYSTEM profile
        Register-PSRepository -Default -InstallationPolicy Trusted -ErrorAction SilentlyContinue
        Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted -ErrorAction Stop
    }
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
    $Feature = Get-WindowsFeature -Name RSAT-AD-PowerShell -ErrorAction SilentlyContinue
    if ($Feature -and -not $Feature.Installed) {
        Write-Log "Installing RSAT-AD-PowerShell..."
        Install-WindowsFeature -Name RSAT-AD-PowerShell -IncludeAllSubFeature -ErrorAction Stop
    } else {
        Write-Log "RSAT-AD-PowerShell is already installed or not applicable."
    }
}
catch {
    Write-Log "Failed to install RSAT Windows Feature: $_" -Level Error
    $ErrorFound = $true
}

# ---------------------------------------------------------------------------
# 5. MODULE INSTALLATION
# ---------------------------------------------------------------------------
foreach ($ModuleName in $ModulesToInstall) {
    try {
        Write-Log "[$ModuleName] Installing/Updating module for AllUsers..."
        
        # Use Install-Module with Scope AllUsers & Force for both fresh installs and updates in SYSTEM context
        Install-Module -Name $ModuleName -Scope AllUsers -Force -AllowClobber -AcceptLicense -ErrorAction Stop
        
        Write-Log "[$ModuleName] Deployment successful."

        # WinGet Engine handling
        if ($ModuleName -eq "Microsoft.WinGet.Client") {
            Write-Log "Attempting to bootstrap WinGet Engine..."
            try {
                Repair-WinGetPackageManager -Confirm:$false -ErrorAction Stop
                Write-Log "WinGet Engine bootstrap completed."
            } catch {
                Write-Log "WinGet Engine bootstrap non-critical warning: $_" -Level Warning
            }
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
    Write-Log "Script completed with one or more errors. Check log at $LogFile" -Level Warning
    exit 3
} else {
    Write-Log "SUCCESS: All modules and features processing complete."
    exit 0
}