<#
.SYNOPSIS
    Configures the Cross-Account Moves OWA Mailbox Policy and assigns it to a user.
.DESCRIPTION
    Creates an OWA Mailbox Policy configured for cross-tenant move support, sets the
    required file and web app permissions, assigns it to a user, and logs the output to C:\Temp.
#>

# ==========================================
# CONFIGURATION VARIABLES (Update Per Tenant)
# ==========================================
$AdminUPN   = "admin@tenantdomain.com"
$TargetUser = "user@tenantdomain.com"
$PolicyName = "AllowCrossAccountMoves-USERNAME-Only"
$LogFolder  = "C:\Temp"

# ==========================================
# LOGGING SETUP
# ==========================================
if (-not (Test-Path -Path $LogFolder)) {
    New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null
}

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$LogFile   = Join-Path -Path $LogFolder -ChildPath "OWAPolicySetup_$Timestamp.log"

function Write-Log {
    param ([string]$Message)$LogLine = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')]$Message"
    Write-Host $LogLine
    Add-Content -Path $LogFile -Value$LogLine
}

Write-Log "=== Starting Single-Tenant OWA Policy Configuration ==="
Write-Log "Admin Account: $AdminUPN"
Write-Log "Target User:  $TargetUser"
Write-Log "Policy Name:  $PolicyName"

# ==========================================
# EXECUTION
# ==========================================
try {
    Write-Log "Connecting to Exchange Online ($AdminUPN)..."
    Connect-ExchangeOnline -UserPrincipalName $AdminUPN -ErrorAction Stop | Out-Null

    # Check if policy already exists
    $ExistingPolicy = Get-OwaMailboxPolicy -Identity$PolicyName -ErrorAction SilentlyContinue

    if (-not $ExistingPolicy) {
        Write-Log "Creating base OWA policy '$PolicyName'..."
        New-OwaMailboxPolicy -Name $PolicyName -ErrorAction Stop | Out-Null
        Write-Log "Policy created successfully."
    } else {
        Write-Log "Policy '$PolicyName' already exists. Proceeding to update parameters..."
    }

    # Configure core file-access and web-editing settings
    Write-Log "Applying file access and web app parameters to policy..."
    Set-OwaMailboxPolicy -Identity $PolicyName `
        -DirectFileAccessOnPrivateComputersEnabled $true `
        -DirectFileAccessOnPublicComputersEnabled $true `
        -WacViewingOnPrivateComputersEnabled $true `
        -WacEditingEnabled $true -ErrorAction Stop
    Write-Log "Policy parameters successfully configured."

    # Assign policy to user
    Write-Log "Assigning policy '$PolicyName' to user '$TargetUser'..."
    Set-CASMailbox -Identity $TargetUser -OwaMailboxPolicy$PolicyName -ErrorAction Stop
    Write-Log "Successfully assigned policy to '$TargetUser'."

    # Verification Query
    Write-Log "Verifying assignment..."
    $UserCheck = Get-CASMailbox -Identity$TargetUser | Select-Object DisplayName, PrimarySmtpAddress, OwaMailboxPolicy
    Write-Log "Verification Result: User '$($UserCheck.DisplayName)' is assigned policy '$($UserCheck.OwaMailboxPolicy)'"

}
catch {
    Write-Log "ERROR: $_"
}
finally {
    Write-Log "Disconnecting Exchange Online session..."
    Disconnect-ExchangeOnline -Confirm:$false | Out-Null
    Write-Log "=== Process Finished. Log saved to: $LogFile ==="
}