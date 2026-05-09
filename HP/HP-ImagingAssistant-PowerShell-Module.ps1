<#
    .SYNOPSIS
        Forcefully installs/updates HPCMSL and HPIA by clearing locked modules.
    
    .EXITCODES
        0    = Success
        1001 = Failed to update PowerShellGet/NuGet
        1002 = Failed to install/force-update HPCMSL Module
        1003 = Failed to download or extract HP Image Assistant
        1004 = Script not running on a 64-bit system
#>

$ErrorActionPreference = "Stop"

$EXIT_SUCCESS = 0
$ERR_PREREQ   = 1001
$ERR_MODULE   = 1002
$ERR_HPIA     = 1003
$ERR_ARCH     = 1004

$LogPath = "C:\temp"
if (-not (Test-Path $LogPath)) { New-Item -Path $LogPath -ItemType Directory -Force | Out-Null }
$LogFile = Join-Path $LogPath ("Force-Install-HPIA_$(Get-Date -Format 'yyyyMMdd_HHmmss').log")

function Write-Log {
    param([string]$Message)
    $Stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$Stamp] $Message" | Out-File -FilePath $LogFile -Append
}

Write-Log "Starting Force HP Imaging Assistant Installation Script."

if ([Environment]::Is64BitOperatingSystem -eq $false) {
    Write-Log "Critical: HPCMSL requires a 64-bit OS."
    exit $ERR_ARCH
}

# 1. Prerequisite Phase
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Write-Log "Ensuring NuGet and PowerShellGet are updated..."
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false | Out-Null
    Install-Module -Name PowerShellGet -Force -AllowClobber -SkipPublisherCheck -Confirm:$false | Out-Null
} catch {
    Write-Log "Prerequisite failure: $($_.Exception.Message)"
    exit $ERR_PREREQ
}

# 2. Force Clear and Install HPCMSL
try {
    Write-Log "Attempting to unload existing HP modules from memory..."
    Get-Module -Name "HP.*" | Remove-Module -ErrorAction SilentlyContinue

    # Identify and kill other PowerShell processes that might lock the files
    $CurrentPID = [System.Diagnostics.Process]::GetCurrentProcess().Id
    $OtherPSSessions = Get-Process powershell, pwsh -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $CurrentPID }
    
    foreach ($Proc in $OtherPSSessions) {
        Write-Log "Terminating conflicting PowerShell process: $($Proc.Id)"
        Stop-Process -Id $Proc.Id -Force -ErrorAction SilentlyContinue
    }

    Write-Log "Installing HPCMSL with -AcceptLicense..."
    # We use -AllowClobber to overwrite 'In Use' files that were just freed
    Install-Module -Name HPCMSL -Force -AllowClobber -Scope AllUsers -AcceptLicense -Confirm:$false
    
    # Verify installation
    if (Get-Module -ListAvailable -Name HPCMSL) {
        Write-Log "HPCMSL Module successfully installed/updated."
    }
} catch {
    Write-Log "HPCMSL Force Installation failure: $($_.Exception.Message)"
    exit $ERR_MODULE
}

# 3. HPIA Phase
try {
    $HPIAPath = "C:\Program Files\HPIA"
    if (-not (Test-Path $HPIAPath)) { New-Item -Path $HPIAPath -ItemType Directory -Force | Out-Null }

    Write-Log "Downloading/Extracting HP Image Assistant..."
    # Explicitly import the fresh module
    Import-Module HPCMSL -Force
    
    Install-HPImageAssistant -Extract -DestinationPath $HPIAPath -Quiet -Confirm:$false
    
    if (Test-Path "$HPIAPath\HPImageAssistant.exe") {
        Write-Log "HP Image Assistant successfully installed at $HPIAPath."
    } else {
        throw "HPImageAssistant.exe missing after extraction."
    }
} catch {
    Write-Log "HPIA installation failure: $($_.Exception.Message)"
    exit $ERR_HPIA
}

Write-Log "Script completed successfully."
exit $EXIT_SUCCESS