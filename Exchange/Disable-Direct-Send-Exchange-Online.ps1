<#
.SYNOPSIS
    Configures Exchange Online to disable Direct Send.

.DESCRIPTION
    This script automates the process of disabling Direct Send at the organization level. 
    It checks for the ExchangeOnlineManagement module, installs it if missing, 
    authenticates the user manually, and updates the Organization Config.
    Logs are saved locally to C:\temp.

.PARAMETER LogPath
    The directory where logs will be stored. Defaults to C:\temp.

.EXAMPLE
    .\Set-ExchangeDirectSend.ps1
#>

[CmdletBinding()]
param (
    [string]$LogPath = "C:\temp"
)

# --- Configuration & Variables ---
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile = Join-Path -Path $LogPath -ChildPath "ExchangeConfig_$($Timestamp).log"
$ModuleName = "ExchangeOnlineManagement"

# --- Functions ---

function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR")]
        [string]$Level = "INFO"
    )
    $Line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] - $Message"
    Write-Host $Line -ForegroundColor (switch($Level) { "ERROR" {"Red"}; "WARNING" {"Yellow"}; Default {"Cyan"} })
    $Line | Out-File -FilePath $LogFile -Append
}

# --- Execution Logic ---

try {
    # 1. Ensure Log Directory Exists
    if (!(Test-Path $LogPath)) {
        New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
    }

    Write-Log "Starting script execution."
    
    # 2. Module Check and Installation
    Write-Log "Checking for $ModuleName module..."
    if (!(Get-Module -ListAvailable -Name $ModuleName)) {
        Write-Log "$ModuleName not found. Attempting installation..." -Level "WARNING"
        Install-Module -Name $ModuleName -Force -AllowClobber -Scope CurrentUser -ErrorAction Stop
        Write-Log "Module installed successfully."
    } else {
        Write-Log "Module $ModuleName is already installed."
    }

    # 3. Connect to Exchange Online
    Write-Log "Initiating manual login to Exchange Online..."
    Connect-ExchangeOnline -ErrorAction Stop
    Write-Log "Successfully connected to Exchange Online."

    # 4. Apply Configuration Change
    Write-Log "Setting RejectDirectSend to `$true`..."
    Set-OrganizationConfig -RejectDirectSend $true -ErrorAction Stop
    Write-Log "Organization configuration updated successfully."

    # 5. Verification
    Write-Log "Verifying current configuration status..."
    $FinalConfig = Get-OrganizationConfig | Select-Object Identity, RejectDirectSend
    Write-Log "Current Identity: $($FinalConfig.Identity)"
    Write-Log "RejectDirectSend Status: $($FinalConfig.RejectDirectSend)"

    if ($FinalConfig.RejectDirectSend -eq $true) {
        Write-Log "Verification Complete: Direct Send is DISABLED."
    } else {
        Write-Log "Verification Failed: Direct Send is still ENABLED." -Level "ERROR"
    }

}
catch {
    Write-Log "A critical error occurred: $($_.Exception.Message)" -Level "ERROR"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level "ERROR"
}
finally {
    # Disconnect to clean up the session
    if (Get-Module -Name $ModuleName) {
        Write-Log "Closing Exchange Online session..."
        Disconnect-ExchangeOnline -Confirm:$false
    }
    Write-Log "Script execution finished. Log saved to: $LogFile"
}