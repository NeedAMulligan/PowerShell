<#
.SYNOPSIS
    Queries Entra ID and Intune for all devices regardless of activity via Direct API.
    Optimized for GCC High with full local logging to C:\temp.

.DESCRIPTION
    1. Connects to Microsoft Graph USGov using the Authentication module.
    2. Retrieves Tenant Name and creates a log file: [Tenant]_AllDeviceLog_[Timestamp].log
    3. Performs direct API calls to Entra and Intune.
    4. Exports result to CSV and closes the session.
    
.EXITCODES
    0 - Success
    1 - Missing Authentication Module
    2 - API or Runtime Error
#>

# Version: 2.0.0 | Resilient IT | Windows PowerShell 5.1
# Read-only inventory: no device changes. Includes Entra-only and Intune-only records.
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# VARIABLES SECTION
# ---------------------------------------------------------------------------
$GraphEnv         = "USGov" 
$LogPath          = "C:\temp"
$Timestamp        = Get-Date -Format "yyyyMMdd_HHmmss"

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

function Get-AllGraphRecords {
    param([Parameter(Mandatory=$true)][string]$Uri)
    do {
        $Page = Invoke-MgGraphRequest -Method GET -Uri $Uri -ErrorAction Stop
        foreach ($Record in $Page.value) { $Record }
        $Uri = $Page.'@odata.nextLink'
    } while ($Uri)
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
    $Global:LogFile = "$LogPath\${TenantName}_AllDeviceLog_$Timestamp.log"
    $ExportFile     = "$LogPath\${TenantName}_AllDevices_$Timestamp.csv"

    Write-LocalLog "--- Start of Audit for $TenantName ---"
    Write-LocalLog "Log File initialized at: $Global:LogFile"

    # 3. Query all Entra ID devices
    Write-LocalLog "Querying all Entra ID devices..."
    $EntraUri = "https://graph.microsoft.us/v1.0/devices?`$select=id,displayName,operatingSystem,approximateLastSignInDateTime,accountEnabled,deviceId"
    $EntraList = @(Get-AllGraphRecords -Uri $EntraUri)

    # 4. Query Intune Devices
    Write-LocalLog "Querying Intune for managed device status..."
    $IntuneUri = "https://graph.microsoft.us/v1.0/deviceManagement/managedDevices?`$select=id,deviceName,lastSyncDateTime,azureADDeviceId,operatingSystem"
    $IntuneList = @(Get-AllGraphRecords -Uri $IntuneUri)

    $Results = New-Object System.Collections.Generic.List[PSCustomObject]

    # 5. Process and Cross-Reference
    Write-LocalLog "Processing $($EntraList.Count) Entra records against Intune data..."
    $MatchedIntune = @{}
    foreach ($E in $EntraList) {
        $Matches = @($IntuneList | Where-Object { $E.deviceId -and $_.azureADDeviceId -and $_.azureADDeviceId -ne '00000000-0000-0000-0000-000000000000' -and $_.azureADDeviceId -eq $E.deviceId })
        if ($Matches.Count -eq 0) { $Matches = @($null) }
        foreach ($I in $Matches) {
            if ($I) { $MatchedIntune[$I.id] = $true }
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

    foreach ($I in $IntuneList) {
        if (-not $MatchedIntune.ContainsKey($I.id)) {
            $Results.Add([PSCustomObject]@{
                TenantName = $TenantName
                DisplayName = $I.deviceName
                AccountStatus = 'Not in Entra'
                EntraLastSeen = $null
                IntuneLastSync = $I.lastSyncDateTime
                OperatingSystem = $I.operatingSystem
                EntraObjectID = $null
                PhysicalDeviceID = $I.azureADDeviceId
                IntuneManagedID = $I.id
            })
        }
    }

    # 6. Export to CSV
    if ($Results.Count -gt 0) {
        $Results | Export-Csv -Path $ExportFile -NoTypeInformation -Encoding UTF8
        Write-LocalLog "SUCCESS: Found $($Results.Count) device inventory rows."
        Write-LocalLog "Export Path: $ExportFile"
    } else {
        Write-LocalLog "No devices found in Entra or Intune." "WARN"
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
