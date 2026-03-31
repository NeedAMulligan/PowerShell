# EXIT CODES
# 0    = Success
# 1001 = SaRAcmd.exe not found in the extracted folder
# 1002 = Failed to create C:\temp or log file
# 1003 = General Script Execution Failure
# 1004 = SaRAcmd executed but returned an error code

$ErrorActionPreference = "Stop"

# Define Paths
$LogDir = "C:\temp"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile = Join-Path $LogDir "SaRA_Office_Scrub_$($Timestamp).log"

# Path where your RMM extracted the ZIP (Update this path as needed)
$ExtractionPath = "C:\temp\SaRA_Enterprise" 
$SaraCmdExe = Join-Path $ExtractionPath "SaRAcmd.exe"

# Ensure Log Directory exists
if (-not (Test-Path $LogDir)) {
    try {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    } catch {
        exit 1002
    }
}

Function Write-Log {
    Param([string]$Message)
    $Entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
    $Entry | Out-File -FilePath $LogFile -Append
}

Write-Log "--- Starting Enterprise SaRA Office Scrub ---"

# Verify SaRAcmd.exe exists
if (-not (Test-Path $SaraCmdExe)) {
    Write-Log "ERROR: SaRAcmd.exe not found at $SaraCmdExe. Check extraction path."
    exit 1001
}

try {
    Write-Log "Executing: SaRAcmd.exe -S OfficeScrub -AcceptEula -All"
    
    # Execution Flags:
    # -S OfficeScrub: The scenario for complete removal
    # -AcceptEula: Silent bypass of the license agreement
    # -All: Removes all detected versions (2013, 2016, 2019, O365, etc.)
    
    $Process = Start-Process -FilePath $SaraCmdExe -ArgumentList "-S OfficeScrub -AcceptEula -All" -Wait -NoNewWindow -PassThru
    
    if ($Process.ExitCode -eq 0) {
        Write-Log "Success: Office products have been queued for removal."
        exit 0
    } else {
        Write-Log "SaRA finished with Exit Code: $($Process.ExitCode)"
        exit 1004
    }
}
catch {
    Write-Log "Exception occurred: $($_.Exception.Message)"
    exit 1003
}