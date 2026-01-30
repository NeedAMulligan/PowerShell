<#
.SYNOPSIS
    Renames a computer based on a prefix and the hardware serial number.
    Includes validation for generic/junk serial numbers.
    
.EXITCODES
    0    = Success / No change needed
    1001 = Script must run as System/Administrator
    1002 = Failed to retrieve Serial Number
    1003 = Generic/Junk Serial Number detected (Abort)
    1004 = Rename failed
#>

# Define Exit Codes
$SUCCESS = 0
$ERR_NOT_ADMIN = 1001
$ERR_NO_SERIAL = 1002
$ERR_GENERIC_SERIAL = 1003
$ERR_RENAME_FAILED = 1004

# --- VARIABLES ---
$CompanyPrefix = "ACME" # Change this per client via RMM variable
$LogDir = "C:\temp"
$ScriptID = "RenameBySerial"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile = Join-Path $LogDir "$($ScriptID)_$($Timestamp).log"

# List of generic serials to reject
$JunkSerials = @(
    "To be filled by O.E.M.",
    "Default String",
    "0123456789",
    "System Serial Number",
    "None",
    "Empty"
)

# --- LOGGING SETUP ---
if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }

function Write-Log {
    param([string]$Message)
    $Msg = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
    $Msg | Out-File -FilePath $LogFile -Append
}

Write-Log "Starting Computer Rename Script for Prefix: $CompanyPrefix"

# 1. Check for Admin Rights (System Context)
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "ERROR: Script not running with administrative privileges."
    exit $ERR_NOT_ADMIN
}

# 2. Get Serial Number
try {
    Write-Log "Querying BIOS for Serial Number..."
    $BiosInfo = Get-CimInstance Win32_Bios -ErrorAction Stop
    $RawSerial = $BiosInfo.SerialNumber.Trim()
    
    if ([string]::IsNullOrWhiteSpace($RawSerial)) { throw "Serial number is null or whitespace." }
}
catch {
    Write-Log "ERROR: Could not retrieve serial number. Details: $($_.Exception.Message)"
    exit $ERR_NO_SERIAL
}

# 3. Validate Serial Number (Anti-Collision)
if ($JunkSerials -contains $RawSerial -or $RawSerial.Length -lt 3) {
    Write-Log "ERROR: Generic or invalid serial detected: '$RawSerial'. Aborting rename to prevent naming collisions."
    exit $ERR_GENERIC_SERIAL
}

# 4. Format New Name (PREFIX-SERIAL)
$TargetName = "$CompanyPrefix-$RawSerial"
if ($TargetName.Length -gt 15) {
    $TargetName = $TargetName.Substring(0, 15)
    Write-Log "WARN: Name truncated to 15 chars (NetBIOS limit): $TargetName"
}

$CurrentName = $env:COMPUTERNAME
if ($CurrentName -eq $TargetName) {
    Write-Log "SUCCESS: Computer is already named $TargetName. No action required."
    exit $SUCCESS
}

# 5. Execute Rename
try {
    Write-Log "Attempting to rename '$CurrentName' to '$TargetName'..."
    Rename-Computer -NewName $TargetName -Force -ErrorAction Stop
    Write-Log "SUCCESS: Computer renamed to $TargetName. Reboot required."
    exit $SUCCESS
}
catch {
    Write-Log "ERROR: Rename failed. Details: $($_.Exception.Message)"
    exit $ERR_RENAME_FAILED
}