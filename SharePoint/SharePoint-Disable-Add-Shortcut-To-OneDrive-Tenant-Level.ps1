<#
.SYNOPSIS
    Disables "Add Shortcut to OneDrive" and audits existing shortcuts.
    
.EXITCODES
    0    = Success
    1001 = Module Installation Failed
    1002 = Connection to SPO Failed
    1003 = Set-SPOTenant Command Failed
    1005 = Insufficient Permissions (Not Admin)
#>

$EXIT_SUCCESS   = 0
$EXIT_MOD_FAIL  = 1001
$EXIT_CONN_FAIL = 1002
$EXIT_SET_FAIL  = 1003
$EXIT_PERM_FAIL = 1005

# --- Variables ---
$SPOAdminUrl = "https://REPLACEME-admin.sharepoint.com"
$LogPath     = "C:\temp"
$ScriptName  = "Disable-SPOShortcuts-Full"
$Timestamp   = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile     = "$LogPath\$($ScriptName)_$($Timestamp).log"

# --- Ensure Log Directory ---
if (!(Test-Path $LogPath)) { New-Item -ItemType Directory -Path $LogPath -Force | Out-Null }

Function Write-AdminLog {
    Param (
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet("Info", "Warning", "Error", "Success")]$Level = "Info"
    )
    $Stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Stamp] [$Level] $Message"
    $LogEntry | Out-File -FilePath $LogFile -Append
    switch ($Level) {
        "Info"    { Write-Host $LogEntry -ForegroundColor Cyan }
        "Warning" { Write-Host $LogEntry -ForegroundColor Yellow }
        "Error"   { Write-Host $LogEntry -ForegroundColor Red }
        "Success" { Write-Host $LogEntry -ForegroundColor Green }
    }
}

# 1. Execution Policy & Admin Check
Write-AdminLog "Starting Script: $ScriptName"

# Check for Admin Privileges
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-AdminLog "CRITICAL: This script must be run as an Administrator." -Level Error
    Read-Host "Press Enter to exit"; exit $EXIT_PERM_FAIL
}

# Set Execution Policy for the current process
Write-AdminLog "Setting Execution Policy to RemoteSigned for this session..."
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force

# 2. Module Pre-flight
Write-AdminLog "Verifying SharePoint Online Module..."
if (!(Get-Module -ListAvailable -Name Microsoft.Online.SharePoint.PowerShell)) {
    try {
        Write-AdminLog "Module not found. Installing now..." -Level Warning
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
        Install-Module -Name Microsoft.Online.SharePoint.PowerShell -Force -AllowClobber -Scope CurrentUser -Confirm:$false
        Write-AdminLog "Module installed successfully." -Level Success
    } catch {
        Write-AdminLog "Module installation failed: $($_.Exception.Message)" -Level Error
        Read-Host "Press Enter to exit"; exit $EXIT_MOD_FAIL
    }
}

# 3. Connection
try {
    Write-AdminLog "Connecting to: $SPOAdminUrl"
    Write-AdminLog "ACTION: Complete the MFA login in the pop-up window." -Level Warning
    Connect-SPOService -Url $SPOAdminUrl
} catch {
    Write-AdminLog "Connection failed. Check URL and MFA status. $($_.Exception.Message)" -Level Error
    Read-Host "Press Enter to exit"; exit $EXIT_CONN_FAIL
}

# 4. Apply Configuration
try {
    Write-AdminLog "Disabling 'Add Shortcut to OneDrive' at Tenant Level..."
    Set-SPOTenant -DisableAddShortcutsToOneDrive $true -Confirm:$false
    $Verify = Get-SPOTenant | Select-Object -ExpandProperty DisableAddShortcutsToOneDrive
    if ($Verify -eq $true) { 
        Write-AdminLog "VERIFIED: Tenant setting is now DISABLED." -Level Success 
    }
} catch {
    Write-AdminLog "Failed to update tenant setting: $($_.Exception.Message)" -Level Error
    Read-Host "Press Enter to exit"; exit $EXIT_SET_FAIL
}

# 5. Post-Change Audit
Write-AdminLog "Scanning for existing shortcuts in Site Collections..."
try {
    $AllSites = Get-SPOSite -Limit All
    $ShortcutReport = @()

    foreach ($Site in $AllSites) {
        $SiteData = Get-SPOSite -Identity $Site.Url -Detailed
        if ($SiteData.IsShortcutSite) {
            Write-AdminLog "Found existing shortcuts in: $($Site.Url)" -Level Warning
            $ShortcutReport += $Site.Url
        }
    }

    if ($ShortcutReport.Count -gt 0) {
        $ReportFile = "$LogPath\Shortcut_Audit_$Timestamp.txt"
        $ShortcutReport | Out-File $ReportFile
        Write-AdminLog "Audit list exported to $ReportFile" -Level Info
    } else {
        Write-AdminLog "No existing shortcuts detected in scanned sites." -Level Success
    }
} catch {
    Write-AdminLog "Audit scan failed or timed out. $($_.Exception.Message)" -Level Error
}

Write-AdminLog "Script Task Completed. Log: $LogFile"
Write-Host ""
Read-Host "Process complete. Press Enter to close this window"
exit $EXIT_SUCCESS