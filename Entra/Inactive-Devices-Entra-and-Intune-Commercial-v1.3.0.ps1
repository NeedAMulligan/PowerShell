<#
.SYNOPSIS
    Export stale devices using the latest Entra device activity or Intune sync, including user and ownership.
.DESCRIPTION
    Read-only Microsoft Graph audit. Intune's assigned user is preferred. When unavailable,
    Entra registered users are queried as a fallback; registration does not prove ownership.
    Multiple registered users are separated with semicolons. Missing associations are left blank.
    DeviceOwnership uses the Intune managedDeviceOwnerType classification (Corporate/Personal);
    devices not matched in Intune or with no definitive Intune classification are Unknown.
    LastKnownActivity is the most recent timestamp across Entra device activity and Intune sync.
    A device is exported when the latest timestamp is older than InactivityDays, or
    when neither source contains an activity timestamp (No Activity Recorded).
    IntuneEnrollmentStatus reflects whether an Intune managed-device record matches.
    ActivityStatus does not identify intentional inventory/spare-device exceptions;
    those require an external asset inventory for validation.
    Outputs a timestamped CSV and log under C:\Temp, prefixed by the tenant domain.
    Requires interactive delegated Graph authentication (not suitable for unattended SYSTEM use).
.PARAMETER InactivityDays
    Number of days since the most recent Entra activity or Intune sync. Default: 90.
.PARAMETER LogPath
    Directory for CSV and log output. Default: C:\Temp.
.EXITCODES
    0 Success; 1 Authentication module unavailable; 2 Graph/runtime failure; 3 Output directory failure.
#>
[CmdletBinding()]
param(
    [ValidateRange(1,3650)][int]$InactivityDays = 90,
    [string]$LogPath = 'C:\Temp'
)

$ErrorActionPreference = 'Stop'
$GraphEnvironment = 'Global'
$GraphRoot = 'https://graph.microsoft.com'
$FallbackTenant = 'Commercial_Export'
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$Threshold = (Get-Date).ToUniversalTime().AddDays(-$InactivityDays)
$script:LogFile = $null
$script:RegistrationFallbackAvailable = $true
$script:RegistrationWarningLogged = $false
$script:GraphSessionStarted = $false

function Write-AuditLog {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR')][string]$Level='INFO')
    $Line = '{0} [{1}] - {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Level,$Message
    Write-Host $Line
    if ($script:LogFile) { Add-Content -LiteralPath $script:LogFile -Value $Line -Encoding UTF8 }
}

function Get-GraphPagedItems {
    param([Parameter(Mandatory=$true)][string]$Uri)
    $Items = New-Object 'System.Collections.Generic.List[object]'
    $Next = $Uri
    while ($Next) {
        $Response = Invoke-MgGraphRequest -Method GET -Uri $Next -ErrorAction Stop
        if ($null -ne $Response.value) {
            foreach ($Item in $Response.value) { [void]$Items.Add($Item) }
        }
        $Next = $Response.'@odata.nextLink'
    }
    return $Items.ToArray()
}

function Get-RegisteredDeviceUsers {
    param([Parameter(Mandatory=$true)][string]$EntraObjectId)
    if (-not $script:RegistrationFallbackAvailable) { return @() }
    try {
        $Uri = "$GraphRoot/v1.0/devices/$EntraObjectId/registeredUsers/microsoft.graph.user?`$select=displayName,mail,userPrincipalName"
        return @(Get-GraphPagedItems -Uri $Uri)
    }
    catch {
        $Text = $_.Exception.Message
        if ($Text -match '(403|Authorization_RequestDenied|Insufficient privileges|Forbidden)') {
            $script:RegistrationFallbackAvailable = $false
            Write-AuditLog 'Entra registered-user lookup is not authorized. Intune associations will still be exported; grant Directory.Read.All if this fallback is needed.' WARN
        }
        elseif (-not $script:RegistrationWarningLogged) {
            $script:RegistrationWarningLogged = $true
            Write-AuditLog "Some Entra registered-user lookups failed (example: $Text). Unresolved user fields will be blank." WARN
        }
        return @()
    }
}

function Get-FirstNonblank {
    param([object[]]$Candidates)
    foreach ($Value in $Candidates) {
        if (-not [string]::IsNullOrWhiteSpace([string]$Value)) { return [string]$Value }
    }
    return ''
}

$ExitCode = 0
try {
    if (-not (Test-Path -LiteralPath $LogPath)) {
        New-Item -Path $LogPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
}
catch {
    Write-Host "Cannot create output directory '$LogPath': $($_.Exception.Message)"
    exit 3
}

try {
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
        Write-AuditLog 'Installing Microsoft.Graph.Authentication for the current user...' WARN
        try { Install-Module -Name Microsoft.Graph.Authentication -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop }
        catch { throw "Microsoft.Graph.Authentication installation failed: $($_.Exception.Message)" }
    }
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

    # The scopes include Directory.Read.All to resolve registered users for unmanaged devices.
    # Intune's assigned user fields are available with DeviceManagementManagedDevices.Read.All.
    $Scopes = @('Device.Read.All','DeviceManagementManagedDevices.Read.All','Organization.Read.All','Directory.Read.All')
    Write-AuditLog "Connecting to Microsoft Graph environment: $GraphEnvironment"
    Connect-MgGraph -Environment $GraphEnvironment -Scopes $Scopes -ContextScope CurrentUser -NoWelcome -ErrorAction Stop | Out-Null
    $script:GraphSessionStarted = $true
    $Context = Get-MgContext
    if (-not $Context -or $Context.Environment -ne $GraphEnvironment) {
        throw "Graph environment mismatch: expected $GraphEnvironment."
    }

    $Org = Get-GraphPagedItems -Uri "$GraphRoot/v1.0/organization?`$select=verifiedDomains,displayName"
    $TenantName = ''
    if ($Org.Count -gt 0) {
        $DefaultDomain = @($Org[0].verifiedDomains | Where-Object { $_.isDefault } | Select-Object -First 1)
        if ($DefaultDomain.Count -gt 0) { $TenantName = [string]$DefaultDomain[0].name }
    }
    if (-not $TenantName) { $TenantName = $FallbackTenant }
    $SafeTenant = $TenantName -replace '[^a-zA-Z0-9._-]', '_'
    $script:LogFile = Join-Path $LogPath ("{0}_StaleDeviceLog_{1}.log" -f $SafeTenant,$Timestamp)
    $ExportFile = Join-Path $LogPath ("{0}_StaleDevices_{1}.csv" -f $SafeTenant,$Timestamp)
    Write-AuditLog "Tenant: $TenantName; inactivity threshold: $InactivityDays days; CSV: $ExportFile"

    # Request all pages. A missing Entra timestamp alone does not imply staleness.
    # Devices lacking *both* activity timestamps are separately identified.
    $EntraUri = "$GraphRoot/v1.0/devices?`$select=id,displayName,operatingSystem,approximateLastSignInDateTime,accountEnabled,deviceId"
    $IntuneUri = "$GraphRoot/v1.0/deviceManagement/managedDevices?`$select=id,deviceName,lastSyncDateTime,azureADDeviceId,userDisplayName,userPrincipalName,emailAddress,userId,managedDeviceOwnerType"
    Write-AuditLog 'Retrieving all Entra devices (paginated)...'
    $EntraDevices = @(Get-GraphPagedItems -Uri $EntraUri)
    Write-AuditLog 'Retrieving all Intune managed devices (paginated)...'
    $IntuneDevices = @(Get-GraphPagedItems -Uri $IntuneUri)
    Write-AuditLog "Loaded $($EntraDevices.Count) Entra records and $($IntuneDevices.Count) Intune records."

    $IntuneByDeviceId = @{}
    foreach ($Item in $IntuneDevices) {
        $Key = ([string]$Item.azureADDeviceId).Trim().ToLowerInvariant()
        if (-not $Key) { continue }
        if (-not $IntuneByDeviceId.ContainsKey($Key)) { $IntuneByDeviceId[$Key] = New-Object 'System.Collections.Generic.List[object]' }
        [void]$IntuneByDeviceId[$Key].Add($Item)
    }

    $Results = New-Object 'System.Collections.Generic.List[object]'
    foreach ($E in $EntraDevices) {
        $EntraDate = $null
        if ($E.approximateLastSignInDateTime) { $EntraDate = ([datetimeoffset]$E.approximateLastSignInDateTime).UtcDateTime }

        $Key = ([string]$E.deviceId).Trim().ToLowerInvariant()
        $Matches = @()
        if ($Key -and $IntuneByDeviceId.ContainsKey($Key)) { $Matches = @($IntuneByDeviceId[$Key].ToArray()) }

        # If multiple Intune entries map to the same Entra registration, retain the
        # most recently synced record to avoid incorrectly reporting an active device.
        $I = $null
        if ($Matches.Count -gt 0) {
            $I = @($Matches | Sort-Object -Property @{Expression={ if ($_.lastSyncDateTime) { ([datetimeoffset]$_.lastSyncDateTime).UtcDateTime } else { [datetime]::MinValue } }} -Descending | Select-Object -First 1)[0]
        }
        $IntuneDate = $null
        if ($I -and $I.lastSyncDateTime) { $IntuneDate = ([datetimeoffset]$I.lastSyncDateTime).UtcDateTime }

        # Evaluate the *latest* recorded device activity. Intune can sync even if
        # nobody signs in; Entra may show recent activity for unmanaged devices.
        $LastKnownActivity = $null
        $LastActivitySource = 'None'
        if ($null -ne $EntraDate) {
            $LastKnownActivity = $EntraDate
            $LastActivitySource = 'Entra'
        }
        if ($null -ne $IntuneDate -and ($null -eq $LastKnownActivity -or $IntuneDate -gt $LastKnownActivity)) {
            $LastKnownActivity = $IntuneDate
            $LastActivitySource = 'Intune'
        }
        if ($null -ne $LastKnownActivity -and $LastKnownActivity -ge $Threshold) { continue }

        $DeviceActivityStatus = 'No Activity Recorded'
        $DaysSinceLastActivity = $null
        if ($null -ne $LastKnownActivity) {
            $DeviceActivityStatus = 'Stale'
            $DaysSinceLastActivity = [int][math]::Floor(((Get-Date).ToUniversalTime() - $LastKnownActivity).TotalDays)
        }
        $IntuneEnrollmentStatus = if ($I) { 'Managed' } else { 'Not Managed' }

        $UserName = ''
        $UserEmail = ''
        $UserUPN = ''
        $UserSource = 'None found'
        if ($I) {
            $UserName = Get-FirstNonblank @($I.userDisplayName)
            $UserUPN = Get-FirstNonblank @($I.userPrincipalName)
            $UserEmail = Get-FirstNonblank @($I.emailAddress,$I.userPrincipalName)
            if ($UserName -or $UserEmail -or $UserUPN) { $UserSource = 'Intune assigned user' }
        }

        # Entra registeredUsers may contain multiple accounts, and is not proof
        # of current device ownership. Only use it when Intune has no association.
        if ($UserSource -eq 'None found') {
            $RegisteredUsers = @(Get-RegisteredDeviceUsers -EntraObjectId ([string]$E.id))
            if ($RegisteredUsers.Count -gt 0) {
                $UserName = (@($RegisteredUsers | ForEach-Object { $_.displayName } | Where-Object { $_ } | Select-Object -Unique) -join '; ')
                $UserUPN = (@($RegisteredUsers | ForEach-Object { $_.userPrincipalName } | Where-Object { $_ } | Select-Object -Unique) -join '; ')
                $UserEmail = (@($RegisteredUsers | ForEach-Object { Get-FirstNonblank @($_.mail,$_.userPrincipalName) } | Where-Object { $_ } | Select-Object -Unique) -join '; ')
                $UserSource = 'Entra registered user (not confirmed owner)'
            }
        }

        # Ownership comes only from Intune; Entra join/registration does not establish ownership.
        $DeviceOwnership = 'Unknown'
        if ($I) {
            switch (([string]$I.managedDeviceOwnerType).ToLowerInvariant()) {
                'company'  { $DeviceOwnership = 'Corporate' }
                'personal' { $DeviceOwnership = 'Personal' }
                default    { $DeviceOwnership = 'Unknown' }
            }
        }

        $Row = [pscustomobject][ordered]@{
            TenantName       = $TenantName
            DisplayName      = [string]$E.displayName
            UserName         = $UserName
            UserEmail        = $UserEmail
            UserPrincipalName= $UserUPN
            UserSource       = $UserSource
            DeviceOwnership  = $DeviceOwnership
            LastKnownActivity = if ($null -ne $LastKnownActivity) { $LastKnownActivity.ToString('o') } else { $null }
            LastActivitySource = $LastActivitySource
            DaysSinceLastActivity = $DaysSinceLastActivity
            DeviceActivityStatus = $DeviceActivityStatus
            IntuneEnrollmentStatus = $IntuneEnrollmentStatus
            EntraObjectID    = $E.id
            PhysicalDeviceId = $E.deviceId
            AccountStatus    = if ($E.accountEnabled) { 'Enabled' } else { 'Disabled' }
            OS               = $E.operatingSystem
            EntraLastSignIn  = $E.approximateLastSignInDateTime
            IntuneLastSync   = if ($I) { $I.lastSyncDateTime } else { $null }
            IntuneManagedID  = if ($I) { $I.id } else { 'Not Managed' }
        }
        [void]$Results.Add($Row)
    }

    # Always create a CSV, even when no stale devices match.
    if ($Results.Count -gt 0) {
        $Results | Export-Csv -Path $ExportFile -NoTypeInformation -Encoding UTF8
    }
    else {
        $Headers = @('TenantName','DisplayName','UserName','UserEmail','UserPrincipalName','UserSource','DeviceOwnership','LastKnownActivity','LastActivitySource','DaysSinceLastActivity','DeviceActivityStatus','IntuneEnrollmentStatus','EntraObjectID','PhysicalDeviceId','AccountStatus','OS','EntraLastSignIn','IntuneLastSync','IntuneManagedID')
        Set-Content -LiteralPath $ExportFile -Value ($Headers -join ',') -Encoding UTF8
    }
    $CorporateCount = @($Results | Where-Object { $_.DeviceOwnership -eq 'Corporate' }).Count
    $PersonalCount = @($Results | Where-Object { $_.DeviceOwnership -eq 'Personal' }).Count
    $UnknownCount = @($Results | Where-Object { $_.DeviceOwnership -eq 'Unknown' }).Count
    Write-AuditLog "Ownership: Corporate=$CorporateCount; Personal=$PersonalCount; Unknown=$UnknownCount"
    $NoActivityCount = @($Results | Where-Object { $_.DeviceActivityStatus -eq 'No Activity Recorded' }).Count
    $StaleWithActivityCount = $Results.Count - $NoActivityCount
    Write-AuditLog "Activity status: Stale=$StaleWithActivityCount; No Activity Recorded=$NoActivityCount (both are included in the export)."
    Write-AuditLog "Completed: $($Results.Count) stale devices exported to $ExportFile"
}
catch {
    $ExitCode = 2
    Write-AuditLog "Critical error: $($_.Exception.Message)" ERROR
}
finally {
    if ($script:GraphSessionStarted) {
        try { Disconnect-MgGraph -ErrorAction Stop | Out-Null; Write-AuditLog 'Microsoft Graph session disconnected.' }
        catch { Write-AuditLog "Could not disconnect Graph session: $($_.Exception.Message)" WARN }
    }
}
exit $ExitCode
