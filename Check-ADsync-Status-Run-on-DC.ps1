<#
.SYNOPSIS
    Interactive Microsoft Entra Sync Diagnostic (V8 - Advanced REST Edition).
.DESCRIPTION
    Fixes the 'BadRequest' error by implementing ConsistencyLevel headers 
    required for complex OData filtering on provisioning errors.
#>

[CmdletBinding()]
param ()

# 1. SETUP & DYNAMIC LOGGING
$LogPath = "C:\temp"
$TimeStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$MachineName = $env:COMPUTERNAME
$FullLogPath = Join-Path $LogPath "EntraSyncAudit_$($MachineName)_$($TimeStamp).csv"

function Write-EngineeringLog {
    param ([string]$Message, [string]$Level = "INFO")
    if (-not (Test-Path $LogPath)) { New-Item $LogPath -ItemType Directory -Force | Out-Null }
    $LogEntry = [PSCustomObject]@{ 
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Level     = $Level 
        Message   = $Message 
    }
    $LogEntry | Export-Csv -Path $FullLogPath -Append -NoTypeInformation
    $Color = switch($Level) { "ERROR" {"Red"} "WARN" {"Yellow"} default {"Gray"} }
    Write-Host "[$Level] $Message" -ForegroundColor $Color
}

# 2. MODULE LOADING (Authentication Only)
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
    Write-Host "[!] Installing Auth Module..." -ForegroundColor Cyan
    Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
}
Import-Module Microsoft.Graph.Authentication -Force

# 3. MAIN EXECUTION
Clear-Host
Write-Host "=========================================================" -ForegroundColor White
Write-Host "   MICROSOFT ENTRA SYNC DIAGNOSTIC - V8 (ADVANCED REST)  " -ForegroundColor White -BackgroundColor DarkMagenta
Write-Host "=========================================================" -ForegroundColor White

try {
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    Connect-MgGraph -Scopes "Organization.Read.All", "User.Read.All" -ContextScope CurrentUser
    Write-EngineeringLog -Message "Connected to Microsoft Graph."
}
catch {
    Write-EngineeringLog -Message "Auth Failed: $($_.Exception.Message)" -Level ERROR
    return
}

# --- DIAGNOSTIC 1: SYNC HEALTH ---
Write-Host "`n[Action] Checking Sync Health..." -ForegroundColor Yellow
try {
    $OrgUri = "https://graph.microsoft.com/v1.0/organization?`$select=onPremisesLastSyncDateTime,onPremisesSyncEnabled"
    $OrgData = Invoke-MgGraphRequest -Method GET -Uri $OrgUri
    $Org = $OrgData.value[0]
    
    if ($null -ne $Org.onPremisesLastSyncDateTime) {
        $LastSync = [datetime]$Org.onPremisesLastSyncDateTime
        $Diff = (Get-Date) - $LastSync
        $Status = if ($Org.onPremisesSyncEnabled) { "Enabled" } else { "Disabled" }
        
        Write-Host "Status: $Status"
        Write-Host "Last Sync: $LastSync ($([math]::Round($Diff.TotalMinutes,0)) mins ago)"
    }
}
catch {
    Write-EngineeringLog -Message "Sync check failed: $($_.Exception.Message)" -Level ERROR
}

# --- DIAGNOSTIC 2: PROVISIONING ERRORS (Advanced Filtering) ---
Write-Host "`n[Action] Checking for object errors (Advanced Query)..." -ForegroundColor Yellow
try {
    # ConsistencyLevel=eventual and $count=true are REQUIRED for filtering on provisioningErrors
    $Headers = @{
        "ConsistencyLevel" = "eventual"
    }
    
    $ErrorUri = "https://graph.microsoft.com/v1.0/users?`$filter=onPremisesProvisioningErrors/any()&`$select=displayName,userPrincipalName,onPremisesProvisioningErrors&`$count=true"
    
    $ErrorData = Invoke-MgGraphRequest -Method GET -Uri $ErrorUri -Headers $Headers
    $Users = $ErrorData.value

    if ($null -ne $Users -and $Users.Count -gt 0) {
        $Results = foreach ($U in $Users) {
            foreach ($E in $U.onPremisesProvisioningErrors) {
                [PSCustomObject]@{
                    DisplayName = $U.displayName
                    UPN         = $U.userPrincipalName
                    Error       = $E.category
                    Property    = $E.propertyCausingError
                    Value       = $E.value
                }
            }
        }
        Write-EngineeringLog -Message "Found $($Results.Count) errors." -Level WARN
        $Results | Out-GridView -Title "Entra Sync Errors"
    }
    else {
        Write-EngineeringLog -Message "No provisioning errors detected."
    }
}
catch {
    # Detailed error logging for REST troubleshooting
    Write-EngineeringLog -Message "REST Error: $($_.Exception.Message)" -Level ERROR
}

Write-Host "`n[Complete] Report generated: $FullLogPath" -ForegroundColor Green
Disconnect-MgGraph | Out-Null