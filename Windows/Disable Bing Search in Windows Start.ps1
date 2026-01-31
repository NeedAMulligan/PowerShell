# EXIT CODES
# 0    = Success
# 1001 = Failed to create log directory
# 1002 = Permissions Error
# 1003 = Critical failure during execution

$LogPath = "C:\temp"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile = Join-Path $LogPath "DisableBing_Aggressive_$($Timestamp).log"

if (!(Test-Path $LogPath)) {
    try { New-Item -Path $LogPath -ItemType Directory -Force | Out-Null } catch { exit 1001 }
}

function Write-Log {
    param([string]$Message)
    $Entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
    Add-Content -Path $LogFile -Value $Entry
}

Write-Log "Starting Aggressive Bing Search Removal..."

if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "ERROR: Script must run with elevated privileges."
    exit 1002
}

if (!(Test-Path "HKU:\")) {
    New-PSDrive -Name HKU -PSProvider Registry -Root HKey_Users | Out-Null
}

# Define Paths
$PolicyPath = "Software\Policies\Microsoft\Windows\Windows Search"
$UserSearchPath = "Software\Microsoft\Windows\CurrentVersion\Search"

function Apply-RegistryFixes {
    param([string]$HivePath)
    try {
        # 1. Policy Level Fixes
        $FullPolicyPath = "Registry::$HivePath\$PolicyPath"
        if (!(Test-Path $FullPolicyPath)) { New-Item -Path $FullRegPath -Force | Out-Null }
        Set-ItemProperty -Path $FullPolicyPath -Name "ConnectedSearchUseWeb" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $FullPolicyPath -Name "DisableSearchBoxSuggestions" -Value 1 -Type DWord -Force

        # 2. User Level Overrides (The 'BingSearchEnabled' fix)
        $FullUserPath = "Registry::$HivePath\$UserSearchPath"
        if (!(Test-Path $FullUserPath)) { New-Item -Path $FullUserPath -Force | Out-Null }
        Set-ItemProperty -Path $FullUserPath -Name "BingSearchEnabled" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $FullUserPath -Name "SearchboxTaskbarMode" -Value 1 -Type DWord -Force # Optional: Sets search to icon only
        
        # 3. Disable Search Highlights (The Bing icons/news in the bar)
        $HighlightPath = "Registry::$HivePath\Software\Microsoft\Windows\CurrentVersion\SearchSettings"
        if (!(Test-Path $HighlightPath)) { New-Item -Path $HighlightPath -Force | Out-Null }
        Set-ItemProperty -Path $HighlightPath -Name "IsSearchHighlightsEnabled" -Value 0 -Type DWord -Force

        Write-Log "Applied all fixes to: $HivePath"
    } catch {
        Write-Log "Error applying to ${HivePath}: $($_.Exception.Message)"
    }
}

# 1. Active Users
$LoadedHives = Get-ChildItem -Path "HKU:\" | Where-Object { $_.Name -match "S-1-5-21-[\d\-]+$" }
foreach ($Hive in $LoadedHives) {
    Apply-RegistryFixes -HivePath "HKEY_USERS\$($Hive.PSChildName)"
}

# 2. Offline Profiles
$UserProfiles = Get-ChildItem -Path "C:\Users" -Directory
foreach ($Profile in $UserProfiles) {
    $NtUserPath = Join-Path $Profile.FullName "NTUSER.DAT"
    if (Test-Path $NtUserPath) {
        $TempName = "Temp_$($Profile.Name)"
        try {
            $LoadStatus = reg load "HKU\$TempName" "$NtUserPath" 2>&1 | Out-String
            if ($LoadStatus -match "The operation completed successfully") {
                Apply-RegistryFixes -HivePath "HKEY_USERS\$TempName"
                [gc]::Collect(); [gc]::WaitForPendingFinalizers()
                reg unload "HKU\$TempName" | Out-Null
                Write-Log "Processed offline: $($Profile.Name)"
            }
        } catch { Write-Log "Skipped locked profile: $($Profile.Name)" }
    }
}

# 3. Hard Refresh of Search Components
Write-Log "Restarting Search Services..."
Stop-Process -Name "SearchHost" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
Restart-Service -Name "WSearch" -Force -ErrorAction SilentlyContinue

Write-Log "Aggressive Removal Complete."
exit 0
