<#
.SYNOPSIS
    Hides the Family Options area in Windows Defender UI via Registry Policy.
    
.DESCRIPTION
    Deployment Method: RMM / System Context
    Exit Codes:
    0    = Success
    1001 = Path Creation Failed
    1002 = Registry Update Failed
    1003 = General Script Error
#>

# Define Exit Codes
$EXIT_SUCCESS = 0
$ERR_PATH_FAIL = 1001
$ERR_REG_FAIL = 1002
$ERR_GENERAL = 1003

# Logging Configuration
$ScriptName = "Set-HideFamilyOptions"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogDir = "C:\temp"
$LogFile = Join-Path -Path $LogDir -ChildPath "$($ScriptName)_$($Timestamp).log"

# Ensure Log Directory Exists
if (!(Test-Path -Path $LogDir)) {
    try {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    } catch {
        # Fallback if C:\temp cannot be created
        $LogFile = ".\$($ScriptName)_$($Timestamp).log"
    }
}

function Write-Log {
    param([string]$Message)
    $Entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
    $Entry | Out-File -FilePath $LogFile -Append -Encoding UTF8
}

Write-Log "Starting Script: $ScriptName"

try {
    $RegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\UI\FamilyOptions"
    $ValueName = "HideFamilyOptions"
    $ValueData = 1

    # Ensure Registry Path Exists
    if (!(Test-Path -Path $RegPath)) {
        Write-Log "Path $RegPath does not exist. Creating..."
        New-Item -Path $RegPath -Force | Out-Null
        if (!(Test-Path -Path $RegPath)) {
            Write-Log "CRITICAL: Failed to create registry path."
            exit $ERR_PATH_FAIL
        }
    }

    # Set Registry Property
    Write-Log "Setting $ValueName to $ValueData at $RegPath"
    Set-ItemProperty -Path $RegPath -Name $ValueName -Value $ValueData -Type DWORD -Force -ErrorAction Stop
    
    Write-Log "Successfully updated registry."
    Write-Log "Final Status: Success."
    exit $EXIT_SUCCESS

} catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    exit $ERR_REG_FAIL
}
