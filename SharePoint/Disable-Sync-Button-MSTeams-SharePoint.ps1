<#
.SYNOPSIS
    Manually configures SharePoint Tenant settings to hide the Sync button.
    Run this from an elevated PowerShell session.
    
.EXITCODES
    0    = Success
    1001 = Module Installation Failed
    1002 = Connection to SPO Failed
    1003 = Set-SPOTenant Configuration Failed
#>

# Define Exit Codes
$exitCode = @{
    Success        = 0
    ModuleFail     = 1001
    ConnectionFail = 1002
    ConfigFail     = 1003
}

# --- MSP Variables (Adjust per client) ---
$TenantAdminUrl = "https://contoso-admin.sharepoint.com"
# -----------------------------------------

# Setup Logging
$ScriptName = $MyInvocation.MyCommand.Name
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogDir = "C:\temp"
$LogFile = "$LogDir\${ScriptName}_$Timestamp.log"

if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

function Write-Step {
    param([string]$Message, [ConsoleColor]$Color = "White")
    $Entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
    $Entry | Out-File -FilePath $LogFile -Append
    Write-Host "[*] $Message" -ForegroundColor $Color
}

Write-Step "Starting Script: $ScriptName" -Color Cyan

# 1. Check/Install SharePoint Online Module
Write-Step "Checking for Microsoft.Online.Sharepoint.PowerShell module..."
if (-not (Get-Module -ListAvailable -Name Microsoft.Online.Sharepoint.PowerShell)) {
    Write-Step "Module not found. Attempting installation..." -Color Yellow
    try {
        # Note: Requires Internet access and Gallery trust
        Install-Module -Name Microsoft.Online.Sharepoint.PowerShell -Force -AllowClobber -Scope CurrentUser -Confirm:$false
        Write-Step "Module installed successfully." -Color Green
    } catch {
        Write-Step "ERROR: Failed to install module. $_" -Color Red
        exit $exitCode.ModuleFail
    }
} else {
    Write-Step "Module already present." -Color Gray
}

# 2. Connect to SPO (Interactive Auth)
Write-Step "Initiating connection to: $TenantAdminUrl"
try {
    # Since this is run on an admin computer, this will trigger the MFA prompt
    Connect-SPOService -Url $TenantAdminUrl
    Write-Step "Authentication successful." -Color Green
} catch {
    Write-Step "ERROR: Connection failed. Ensure you have Global Admin or SharePoint Admin rights. $_" -Color Red
    exit $exitCode.ConnectionFail
}

# 3. Apply Configuration
Write-Step "Applying: HideSyncButtonOnTeamSite = $true" -Color Yellow
try {
    Set-SPOTenant -HideSyncButtonOnTeamSite $true
    Write-Step "Tenant configuration updated successfully." -Color Green
} catch {
    Write-Step "ERROR: Failed to update tenant settings. $_" -Color Red
    exit $exitCode.ConfigFail
}

Write-Step "Process Complete. Log saved to: $LogFile" -Color Cyan
exit $exitCode.Success