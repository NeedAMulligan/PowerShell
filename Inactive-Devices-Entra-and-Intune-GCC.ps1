<#
.SYNOPSIS
    Queries Entra ID and Intune for stale devices (90+ days) via Direct API.
    Optimized for GCC High with full local logging to C:\temp.

.DESCRIPTION
    1. Connects to Microsoft Graph USGov using the Authentication module.
    2. Retrieves Tenant Name and creates a log file: [Tenant]_StaleDeviceLog_[Timestamp].log
    3. Performs direct API calls to Entra and Intune.
    4. Exports result to CSV and closes the session.
    
.EXITCODES
    0 - Success
    1 - Missing Authentication Module
    2 - API or Runtime Error
#>

# ---------------------------------------------------------------------------
# VARIABLES SECTION
# ---------------------------------------------------------------------------
$InactivityDays   = 90
$GraphEnv         = "USGov" 
$LogPath          = "C:\temp"
$Timestamp        = Get-Date -Format "yyyyMMdd_HHmmss"
$TargetDateISO    = (Get-Date).AddDays(-$InactivityDays).ToString("yyyy-MM-ddTHH:mm:ssZ")

# The LogFile path is initialized as $null and updated once the Tenant Name is known
$Global:LogFile   = $null 

# ---------------------------------------------------------------------------
# FUNCTIONS
# ---------------------------------------------------------------------------

function Write-LocalLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")]$Level = "INFO"
    )
    
    $Color = switch($Level) { 
        "ERROR" {"Red"} 
        "WARN"  {"Yellow"} 
        Default {"Cyan"} 
    }

    $LogEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] - $Message"
    
    # Output to Console
    Write-Host $LogEntry -ForegroundColor $Color
    
    # Output to File if the LogFile path has been defined
    if ($Global:LogFile) {
        $LogEntry | Out-File -FilePath $Global:LogFile -Append
    }
}

# ---------------------------------------------------------------------------
# MAIN EXECUTION
# ---------------------------------------------------------------------------

Try {
    # Ensure local directory exists
    if (!(Test-Path $LogPath)) { 
        New-Item $LogPath -ItemType Directory -Force | Out-Null 
    }

    # 1. Verify Authentication Module
    if (!(Get-Module -ListAvailable -Name "Microsoft.Graph.Authentication")) {
        Write-LocalLog "Authentication module missing. Please install Microsoft.Graph.Authentication." "ERROR"
        exit 1
    }

    Write-LocalLog "Connecting to Microsoft Graph ($GraphEnv)..."
    Connect-MgGraph -Environment $GraphEnv -Scopes "Device.Read.All", "DeviceManagementManagedDevices.Read.All", "Organization.Read.All" -ContextScope CurrentUser

    # 2. Get Tenant Name & Initialize Logging
    Write-LocalLog "Retrieving Tenant information for file naming..."
    $OrgResult  = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.us/v1.0/organization"
    $TenantName = ($OrgResult.value[0].verifiedDomains | Where-Object { $_.isDefault }).name
    if (!$TenantName) { $TenantName = "GCCHigh_Export" }

    # Set Global Log and Export Paths
    $Global:LogFile = "$LogPath\${TenantName}_StaleDeviceLog_$Timestamp.log"
    $ExportFile     = "$LogPath\${TenantName}_StaleDevices_$Timestamp.csv"

    Write-LocalLog "--- Start of Audit for $TenantName ---"
    Write-LocalLog "Log File initialized at: $Global:LogFile"

    # 3. Query Entra ID Devices (Server-side filter)
    Write-LocalLog "Querying Entra ID for devices inactive since $TargetDateISO..."
    $EntraUri = "https://graph.microsoft.us/v1.0/devices?`$select=id,displayName,operatingSystem,approximateLastSignInDateTime,accountEnabled,deviceId&`$filter=approximateLastSignInDateTime le $TargetDateISO"
    $EntraData = Invoke-MgGraphRequest -Method GET -Uri $EntraUri
    $EntraList = $EntraData.value

    # 4. Query Intune Devices
    Write-LocalLog "Querying Intune for managed device status..."
    $IntuneUri = "https://graph.microsoft.us/v1.0/deviceManagement/managedDevices?`$select=id,deviceName,lastSyncDateTime,azureADDeviceId"
    $IntuneData = Invoke-MgGraphRequest -Method GET -Uri $IntuneUri
    $IntuneList = $IntuneData.value

    $Results = New-Object System.Collections.Generic.List[PSCustomObject]

    # 5. Process and Cross-Reference
    Write-LocalLog "Processing $($EntraList.Count) Entra records against Intune data..."
    foreach ($E in $EntraList) {
        $I = $IntuneList | Where-Object { $_.azureADDeviceId -eq $E.deviceId }
        
        $IntuneDate = if($I.lastSyncDateTime) { [DateTime]$I.lastSyncDateTime } else { $null }
        $ThresholdDate = [DateTime]$TargetDateISO

        # Flag if Intune is also stale or not managed
        if ($null -eq $IntuneDate -or $IntuneDate -lt $ThresholdDate) {
            $Results.Add([PSCustomObject]@{
                TenantName        = $TenantName
                DisplayName       = $E.displayName
                AccountStatus     = if($E.accountEnabled){"Enabled"}else{"Disabled"}
                EntraLastSeen     = $E.approximateLastSignInDateTime
                IntuneLastSync    = $I.lastSyncDateTime
                OperatingSystem   = $E.operatingSystem
                EntraObjectID     = $E.id
                PhysicalDeviceID  = $E.deviceId
                IntuneManagedID   = if($I.id){$I.id}else{"Unmanaged"}
            })
        }
    }

    # 6. Export to CSV
    if ($Results.Count -gt 0) {
        $Results | Export-Csv -Path $ExportFile -NoTypeInformation
        Write-LocalLog "SUCCESS: Found $($Results.Count) stale devices."
        Write-LocalLog "Export Path: $ExportFile"
    } else {
        Write-LocalLog "No stale devices found matching the 90-day criteria." "WARN"
    }

} Catch {
    Write-LocalLog "CRITICAL ERROR: $($_.Exception.Message)" "ERROR"
    exit 2
} Finally {
    if (Get-MgContext) {
        Write-LocalLog "Cleaning up session and disconnecting..."
        Disconnect-MgGraph
    }
}

exit 0