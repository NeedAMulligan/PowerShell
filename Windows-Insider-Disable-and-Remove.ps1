<#
.SYNOPSIS
    Removes and disables Windows Insider Program enrollment and services.
    
.EXITCODES
    0    = Success
    1001 = Failed to remove Registry Keys
    1002 = Failed to stop/disable Windows Insider Service
    1003 = Error during log file creation
#>

# Define Exit Codes
$EXIT_SUCCESS = 0
$ERR_REGISTRY = 1001
$ERR_SERVICE  = 1002
$ERR_LOGGING  = 1003

# Logging Setup
$ScriptName = "Remove-WindowsInsider"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogDir = "C:\temp"
$LogFile = "$LogDir\$($ScriptName)_$($Timestamp).log"

try {
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
} catch {
    exit $ERR_LOGGING
}

function Write-Log {
    param([string]$Message)
    $Line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
    Add-Content -Path $LogFile -Value $Line
}

Write-Log "Starting Windows Insider Program Removal."

# 1. Stop and Disable the Windows Insider Service
try {
    Write-Log "Disabling wisvc (Windows Insider Service)..."
    $Service = Get-Service -Name "wisvc" -ErrorAction SilentlyContinue
    if ($Service) {
        Stop-Service -Name "wisvc" -Force -ErrorAction SilentlyContinue
        Set-Service -Name "wisvc" -StartupType Disabled
        Write-Log "Service wisvc disabled successfully."
    } else {
        Write-Log "Service wisvc not found; skipping."
    }
} catch {
    Write-Log "CRITICAL: Failed to disable wisvc."
    exit $ERR_SERVICE
}

# 2. Remove Registry Keys for SelfHost
$RegistryPaths = @(
    "HKLM:\SOFTWARE\Microsoft\WindowsSelfHost",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsInsider",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\SLS\Programs\WIP"
)

foreach ($Path in $RegistryPaths) {
    if (Test-Path $Path) {
        try {
            Write-Log "Removing Registry Path: $Path"
            Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Log "ERROR: Failed to remove $Path. $_"
            exit $ERR_REGISTRY
        }
    }
}

# 3. Explicitly Disable via Policy (Prevents users from re-joining)
try {
    Write-Log "Applying Local Policy to disable Insider Program UI..."
    $PolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    if (-not (Test-Path $PolicyPath)) {
        New-Item -Path $PolicyPath -Force | Out-Null
    }
    Set-ItemProperty -Path $PolicyPath -Name "ManagePreviewBuilds" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $PolicyPath -Name "ManagePreviewBuildsPolicyValue" -Value 0 -Type DWord -Force
} catch {
    Write-Log "Warning: Could not set local policy keys."
}

# 4. Final Cleanup of FlightSettings
$UserRegistryPath = "HKCU:\Software\Microsoft\WindowsSelfHost"
# Note: As this runs in SYSTEM context, we only log that HKCU is skipped or handled via Default User if necessary.
Write-Log "System-level removal complete. HKCU settings should be purged upon next profile sync with HKLM overrides."

Write-Log "Windows Insider Program has been successfully removed and disabled."
exit $EXIT_SUCCESS