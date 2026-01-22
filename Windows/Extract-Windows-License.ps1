<#
.SYNOPSIS
    Extracts Windows License Key from BIOS and Registry.
    
.EXITCODES
    0    = Success
    1001 = Failed to create Log Directory
    1002 = Critical error during key extraction
#>

# Define Exit Codes
$exitSuccess = 0
$errLogDir   = 1001
$errCritical = 1002

# Logic for dynamic logging
$ScriptName = "Extract-WindowsLicense"
$Timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$LogDir     = "C:\temp"
$LogFile    = "$LogDir\${ScriptName}_$Timestamp.log"

# Ensure log directory exists
try {
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
} catch {
    exit $errLogDir
}

function Write-Log {
    param([string]$Message)
    $Entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
    Add-Content -Path $LogFile -Value $Entry
    Write-Output $Message # Allows RMM to capture output
}

Write-Log "Starting License Extraction Script..."

try {
    # 1. Attempt to get BIOS Embedded Key (OEM)
    Write-Log "Querying MSDM (BIOS) Table for OEM Key..."
    $BIOSKey = (Get-CimInstance -ClassName SoftwareLicensingService).OA3xOriginalProductKey
    
    if (-not $BIOSKey) {
        # Fallback for older WMI versions/Hardware
        $BIOSKey = (Get-CimInstance -Namespace root/StandardCimv2 -ClassName MSFT_SoftwareLicensingProduct | Where-Object { $_.PartialProductKey }).ProductKeyID
    }

    # 2. Get OS Description and License Status
    $OSInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    $LicenseInfo = Get-CimInstance -ClassName SoftwareLicensingProduct | Where-Object { $_.PartialProductKey -and $_.Name -like "*Windows*" }

    Write-Log "Operating System: $($OSInfo.Caption)"
    Write-Log "License Status: $($LicenseInfo.LicenseStatus)"
    
    if ($BIOSKey) {
        Write-Log "Found BIOS/OEM Key: $BIOSKey"
    } else {
        Write-Log "No BIOS/OEM key found (Common in Retail/VMs/Volume Licensing)."
    }

    # 3. Get currently active Partial Key
    $PartialKey = $LicenseInfo.PartialProductKey
    Write-Log "Active Partial Product Key: $PartialKey"

    Write-Log "Extraction Complete."
    exit $exitSuccess

} catch {
    Write-Log "CRITICAL ERROR: $($_.Exception.Message)"
    exit $errCritical
}
