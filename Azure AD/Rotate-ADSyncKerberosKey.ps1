<#
.SYNOPSIS
    Standard Operating Procedure (SOP) script for Kerberos Key Rotation.
.DESCRIPTION
    1. Validates local environment and modules.
    2. Performs a double rotation for maximum security.
    3. Verifies success via AD 'pwdLastSet' attribute.
    4. Logs all actions to C:\temp.
.NOTES
    Run this script every 180 days or after admin staff turnover.
#>

# ---------------------------------------------------------------------------
# 1. VARIABLES & CONFIGURATION
# ---------------------------------------------------------------------------
$Config = @{
    LogDirectory    = "C:\temp"
    LogName         = "Manual_SSO_Rotation_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    SSOAccountName  = "AZUREADSSOACC"
    ModulePath      = "C:\Program Files\Microsoft Azure Active Directory Connect\AzureADSSO.psd1"
    WaitTimeSeconds = 120 # 2-minute replication buffer
}

$LogPath = Join-Path $Config.LogDirectory $Config.LogName

# ---------------------------------------------------------------------------
# 2. HELPER FUNCTIONS
# ---------------------------------------------------------------------------

function Write-Log {
    param(
        [Parameter(Mandatory=$true)] [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")] [string]$Level = "INFO"
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] [$Level] $Message"
    
    switch ($Level) {
        "INFO"  { Write-Host $LogEntry -ForegroundColor Cyan }
        "WARN"  { Write-Host $LogEntry -ForegroundColor Yellow }
        "ERROR" { Write-Host $LogEntry -ForegroundColor Red }
    }
    
    if (-not (Test-Path $Config.LogDirectory)) { New-Item $Config.LogDirectory -ItemType Directory | Out-Null }
    $LogEntry | Out-File -FilePath $LogPath -Append
}

function Get-SSOPasswordTimestamp {
    try {
        $Searcher = [adsisearcher]"(&(objectCategory=computer)(name=$($Config.SSOAccountName)))"
        $Result = $Searcher.FindOne()
        if ($Result) {
            return [datetime]::FromFileTime($Result.Properties.pwdlastset[0])
        }
    } catch { return $null }
}

# ---------------------------------------------------------------------------
# 3. MAIN EXECUTION
# ---------------------------------------------------------------------------
try {
    Write-Log "Initializing Local Kerberos Rotation Process."

    # Administrative Check
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Log "ERROR: You must run this script as an Administrator." "ERROR"
        exit 1
    }

    # Module Check
    if (-not (Test-Path $Config.ModulePath)) {
        Write-Log "ERROR: AzureADSSO module not found. Run on the AD Connect Server." "ERROR"
        exit 5
    }
    Import-Module $Config.ModulePath -ErrorAction Stop

    # Capture Baseline Timestamp
    $InitialTS = Get-SSOPasswordTimestamp
    Write-Log "Baseline: $($Config.SSOAccountName) last updated at $InitialTS"

    # Capture Credentials once
    Write-Log "ACTION: Please enter LOCAL Domain Admin credentials (DOMAIN\User)."
    $OnPremCreds = Get-Credential
    
    # Initialize Cloud Context
    Write-Log "ACTION: A Microsoft Sign-in window will now appear. Use Global Admin credentials."
    New-AzureADSSOAuthenticationContext -ErrorAction Stop

    # Start Double Rotation
    for ($i = 1; $i -le 2; $i++) {
        Write-Log "--- Starting Rotation Cycle $i of 2 ---"
        Update-AzureADSSOForest -OnPremCredentials $OnPremCreds -ErrorAction Stop
        Write-Log "Cycle $i complete."

        if ($i -eq 1) {
            Write-Log "Waiting $($Config.WaitTimeSeconds)s for replication..."
            for ($j = $Config.WaitTimeSeconds; $j -gt 0; $j--) {
                Write-Progress -Activity "AD Replication Sleep" -Status "$j seconds remaining" -PercentComplete (($Config.WaitTimeSeconds - $j) / $Config.WaitTimeSeconds * 100)
                Start-Sleep -Seconds 1
            }
        }
    }

    # Final Verification
    $FinalTS = Get-SSOPasswordTimestamp
    $SSOStatus = Get-AzureADSSOStatus
    
    if ($FinalTS -gt $InitialTS -and $SSOStatus.AzureADSSOEnabled) {
        Write-Log "SUCCESS: Kerberos key rotated twice. New AD timestamp: $FinalTS"
    } else {
        Write-Log "WARNING: Rotation completed, but verification failed. Check logs." "WARN"
    }

} catch {
    Write-Log "CRITICAL ERROR: $($_.Exception.Message)" "ERROR"
} finally {
    Write-Log "Process ended. Log saved to $LogPath"
    Write-Host "`nPress any key to exit..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}