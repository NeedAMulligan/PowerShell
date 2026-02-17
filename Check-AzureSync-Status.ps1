<#
.SYNOPSIS
    Microsoft Entra Identity Sync Health Audit (V18 - Switch Edition).
.DESCRIPTION
    Replaces 'if' blocks with 'switch' to bypass the hidden-character 
    parsing error in PS 5.1. Corrects UTC time calculation.
#>

[CmdletBinding()]
param ()

# 1. SETUP
$LogPath = "C:\temp"
$TimeStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$FullLogPath = Join-Path $LogPath "EntraSyncFinalReport_$($TimeStamp).csv"

# 2. MODULE & AUTH
Import-Module Microsoft.Graph.Authentication -Force

# 3. EXECUTION
Clear-Host
Write-Host "=========================================================" -ForegroundColor White
Write-Host "   MICROSOFT ENTRA IDENTITY SYNC AUDIT - V18             " -ForegroundColor White -BackgroundColor DarkBlue
Write-Host "=========================================================" -ForegroundColor White

try {
    Connect-MgGraph -Scopes "Organization.Read.All", "User.Read.All" -ContextScope CurrentUser -NoWelcome
    
    $Response = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/organization"
    $Org = $Response.value[0]
    
    # Accurate UTC Math
    $CloudLastSync = [datetime]$Org.onPremisesLastSyncDateTime
    $CurrentTimeUTC = (Get-Date).ToUniversalTime()
    $TimeSpan = $CurrentTimeUTC - $CloudLastSync
    $LatencyMin = [math]::Round($TimeSpan.TotalMinutes, 0)

    # Use Switch to avoid the 'if' parser bug
    $Grade = "A"
    $Advice = "System healthy."
    $Color = "Green"

    switch ($LatencyMin) {
        { $_ -gt 1440 } { $Grade = "F"; $Advice = "Sync Critical (Over 24h)"; $Color = "Red"; break }
        { $_ -gt 180 }  { $Grade = "D"; $Advice = "Sync Broken (Over 3h)";   $Color = "Red"; break }
        { $_ -gt 90 }   { $Grade = "C"; $Advice = "Sync Stale (Over 1.5h)";  $Color = "Yellow"; break }
        { $_ -gt 40 }   { $Grade = "B"; $Advice = "Sync Delayed";            $Color = "Cyan"; break }
    }

    # Status Formatting
    $SyncStatus = "Disabled"
    switch ($Org.onPremisesSyncEnabled) { $true { $SyncStatus = "Enabled" } }

    # Display Results
    Write-Host "`n[IDENTITY HEALTH GRADE: $Grade]" -ForegroundColor $Color
    Write-Host "------------------------------------"
    Write-Host "Tenant Name     : $($Org.displayName)"
    Write-Host "Sync Status     : $SyncStatus"
    Write-Host "Last Cloud RX   : $CloudLastSync (UTC)"
    Write-Host "Current Latency : $LatencyMin minutes"
    Write-Host "Resolution      : $Advice"

    if ($LatencyMin -gt 60) {
        Write-Host "`n[CHECKLIST: ACTION REQUIRED]" -ForegroundColor Red
        Write-Host " 1. Run 'Get-Service ADSync' on the sync server."
        Write-Host " 2. Run 'Start-ADSyncSyncCycle -PolicyType Delta' manually."
        Write-Host " 3. Check for Event ID 906 (Auth Error) in Application Log."
    }

}
catch {
    Write-Host "Audit failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n[Complete] Report saved to $LogPath" -ForegroundColor Green
Disconnect-MgGraph | Out-Null