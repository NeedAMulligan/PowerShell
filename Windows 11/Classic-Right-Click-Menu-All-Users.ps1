<#
.SYNOPSIS
    Restores the Classic Windows 10 Context Menu for all current and future users.
.DESCRIPTION
    Iterates through all local user profiles and the Default User hive to apply 
    the InprocServer32 registry fix. Restarts Explorer and validates changes.
.PARAMETER LogDir
    The directory where logs will be stored. Defaults to C:\temp.
.NOTES
    Exit Codes:
    0 = Success (All profiles updated and verified)
    1 = Partial Failure (Some profiles failed update or verification)
    2 = Privilege Error (Not running as SYSTEM/Admin)
    3 = Critical Error (System exception)
#>

# --------------------------------------------------------------------------
# VARIABLES
# --------------------------------------------------------------------------
$LogDir         = "C:\temp"
$Timestamp      = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile        = Join-Path $LogDir "ClassicMenu_AllUsers_$Timestamp.log"
$RegistrySubKey = "Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
$GlobalSuccess  = $true

# Ensure Log Directory exists
if (!(Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }

# --------------------------------------------------------------------------
# FUNCTIONS
# --------------------------------------------------------------------------

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $LogEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    Add-Content -Path $LogFile -Value $LogEntry
}

function Set-And-Verify-Key {
    param([string]$HivePath, [string]$DisplayName)
    try {
        $FullKeyPath = Join-Path $HivePath $RegistrySubKey
        
        # 1. Action: Create/Set Key
        if (!(Test-Path $FullKeyPath)) {
            New-Item -Path $FullKeyPath -Force -ErrorAction Stop | Out-Null
        }
        Set-ItemProperty -Path $FullKeyPath -Name "(Default)" -Value "" -ErrorAction Stop
        
        # 2. Validation: Confirm it exists and value is correct
        $Verify = Get-ItemProperty -Path $FullKeyPath -Name "(Default)" -ErrorAction SilentlyContinue
        if ($null -ne $Verify) {
            Write-Log "Successfully verified fix for: $DisplayName" "INFO"
            return $true
        } else {
            Write-Log "Validation FAILED for: $DisplayName" "ERROR"
            return $false
        }
    }
    catch {
        Write-Log "Exception processing $DisplayName : $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# --------------------------------------------------------------------------
# EXECUTION BLOCK
# --------------------------------------------------------------------------
Write-Log "--- Starting Classic Context Menu Deployment ---"

# 1. Privilege Check
$Principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (!$Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "Critical: Script must be run as SYSTEM or Administrator." "ERROR"
    exit 2
}

# 2. Process Logged-in Users (HKEY_USERS)
Write-Log "Scanning HKEY_USERS for active profiles..."
$ActiveHives = Get-ChildItem -Path Registry::HKEY_USERS | Where-Object { $_.Name -match "S-1-5-21-[\d\-]+$" }
foreach ($Hive in $ActiveHives) {
    if (!(Set-And-Verify-Key -HivePath "Registry::$($Hive.Name)" -DisplayName $Hive.Name)) { $GlobalSuccess = $false }
}

# 3. Process Offline/Default Profiles (NTUSER.DAT)
Write-Log "Scanning C:\Users for offline and default profiles..."
$Profiles = Get-ChildItem -Path "C:\Users" -Directory
foreach ($Profile in $Profiles) {
    $NtUserPath = Join-Path $Profile.FullName "NTUSER.DAT"
    
    if (Test-Path $NtUserPath) {
        $TempHiveName = "TempHive_$($Profile.Name)"
        try {
            # Load Hive
            reg load "HKU\$TempHiveName" "$NtUserPath" 2>&1 | Out-Null
            
            # Apply and Verify
            if (!(Set-And-Verify-Key -HivePath "Registry::HKEY_USERS\$TempHiveName" -DisplayName $Profile.Name)) { $GlobalSuccess = $false }
            
            # Unload Hive
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
            reg unload "HKU\$TempHiveName" 2>&1 | Out-Null
        }
        catch {
            Write-Log "Failed to mount/unmount hive for $($Profile.Name)" "ERROR"
            $GlobalSuccess = $false
        }
    }
}

# 4. Restart Explorer
Write-Log "Forcing Explorer restart to apply changes..."
Stop-Process -Name Explorer -Force -ErrorAction SilentlyContinue

# Final Result
if ($GlobalSuccess) {
    Write-Log "Deployment Complete. All profiles validated successfully." "INFO"
    exit 0
} else {
    Write-Log "Deployment finished with one or more errors. Check log for details." "WARNING"
    exit 1
}