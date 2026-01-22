<#
.SYNOPSIS
    Extracts the full hardware-embedded Windows License Key for MSP auditing.
    
.EXITCODES
    0    = Success
    1001 = Failed to create Log Directory
    1002 = Critical error during extraction
#>

# Define Exit Codes
$exitSuccess = 0
$errLogDir   = 1001
$errCritical = 1002

# Logic for dynamic logging
$ScriptName = "Get-WindowsFullLicense"
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
    Write-Output $Message
}

Write-Log "Starting Full License Extraction..."

try {
    # 1. Direct Query for the Full OA3x Key
    Write-Log "Querying SoftwareLicensingService for OA3xOriginalProductKey..."
    $FullKey = (Get-CimInstance -ClassName SoftwareLicensingService -Property OA3xOriginalProductKey).OA3xOriginalProductKey
    
    # 2. Query for License Metadata (OS version and Partial Key for context)
    $OSInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    $LicenseInfo = Get-CimInstance -ClassName SoftwareLicensingProduct | Where-Object { $_.PartialProductKey -and $_.Name -like "*Windows*" }

    Write-Log "OS Caption: $($OSInfo.Caption)"
    
    # 3. Log the Results
    if ($null -ne $FullKey -and $FullKey -ne "") {
        Write-Log "--------------------------------------------------"
        Write-Log "FULL HARDWARE LICENSE KEY: $FullKey"
        Write-Log "--------------------------------------------------"
    } else {
        Write-Log "RESULT: No Full Hardware Key found (Could be a Retail, Volume, or Virtual Machine license)."
    }

    if ($LicenseInfo.PartialProductKey) {
        Write-Log "Active Partial Key (for reference): $($LicenseInfo.PartialProductKey)"
    }

    Write-Log "Extraction Process Finished Successfully."
    exit $exitSuccess

} catch {
    Write-Log "CRITICAL ERROR: $($_.Exception.Message)"
    exit $errCritical
}
