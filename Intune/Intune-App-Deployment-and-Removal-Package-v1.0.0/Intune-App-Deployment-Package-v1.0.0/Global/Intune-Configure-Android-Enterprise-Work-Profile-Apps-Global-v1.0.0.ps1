<#
.SYNOPSIS
    Approves, synchronizes, discovers, and assigns Managed Google Play apps in Microsoft Intune.

.DESCRIPTION
    Production-oriented automation for Android Enterprise work profile deployments.

    The script:
      - Connects to Microsoft Graph.
      - Confirms that Intune is bound to Managed Google Play.
      - Detects existing Android Managed Google Play apps by package ID.
      - Approves missing apps through the Managed Google Play enterprise integration.
      - Triggers an Intune Managed Google Play synchronization.
      - Waits for approved apps to appear in Intune.
      - Assigns required or available apps to All Licensed Users.
      - Uses High Priority automatic updates by default.
      - Preserves unrelated assignments.
      - Replaces only an incorrect All Licensed Users assignment.
      - Logs to C:\Temp and exports a CSV result report.

.NOTES
    Script version: 1.0.0
    Cloud: Global Microsoft 365

    Required Microsoft Graph permissions:
      DeviceManagementApps.ReadWrite.All
      DeviceManagementConfiguration.ReadWrite.All

    Managed Google Play must already be connected to the Intune tenant.

    Approval through approveApps is documented for application permission.
    For fully unattended approval, use TenantId, ClientId, and CertificateThumbprint.
    Interactive delegated authentication can still assign and synchronize apps, but
    approval can be blocked by the tenant/API permission model. The script reports
    that condition clearly rather than creating duplicate app objects.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$TenantId,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ClientId,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$CertificateThumbprint,

    [Parameter()]
    [ValidateSet('default', 'postponed', 'priority')]
    [string]$AutoUpdateMode = 'priority',

    [Parameter()]
    [ValidateRange(60, 1800)]
    [int]$SyncTimeoutSeconds = 600,

    [Parameter()]
    [ValidateRange(5, 60)]
    [int]$PollIntervalSeconds = 15,

    [Parameter()]
    [switch]$SkipApproval
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptVersion = '1.0.0'
$GraphV1BaseUri = 'https://graph.microsoft.com/v1.0'
$GraphBetaBaseUri = 'https://graph.microsoft.com/beta'
$GraphEnvironment = 'Global'
$CloudLabel = 'Global'
$RequiredScopes = @(
    'DeviceManagementApps.ReadWrite.All',
    'DeviceManagementConfiguration.ReadWrite.All'
)

$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogDirectory = 'C:\Temp'
$LogFile = Join-Path $LogDirectory "Intune-Android-Enterprise-Apps-$CloudLabel-$Timestamp.log"
$CsvFile = Join-Path $LogDirectory "Intune-Android-Enterprise-Apps-$CloudLabel-$Timestamp.csv"

if (-not (Test-Path -LiteralPath $LogDirectory)) {
    New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
}

$Results = [System.Collections.Generic.List[object]]::new()

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $line = '[{0}] {1}' -f $Level, $Message
    Add-Content -LiteralPath $LogFile -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $line)

    $color = switch ($Level) {
        'SUCCESS' { 'Green' }
        'WARNING' { 'Yellow' }
        'ERROR'   { 'Red' }
        default   { 'Cyan' }
    }

    Write-Host $line -ForegroundColor $color
}

function Get-ObjectMemberValue {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($key in $InputObject.Keys) {
            if ([string]$key -ieq $Name) {
                return $InputObject[$key]
            }
        }
        return $null
    }

    $property = $InputObject.PSObject.Properties |
        Where-Object { $_.Name -ieq $Name } |
        Select-Object -First 1

    if ($null -ne $property) {
        return $property.Value
    }

    return $null
}

function Get-GraphErrorMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
        return $ErrorRecord.ErrorDetails.Message
    }

    return $ErrorRecord.Exception.Message
}

function Invoke-IntuneGraphRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PATCH', 'DELETE')]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter()]
        [AllowNull()]
        [object]$Body,

        [Parameter()]
        [ValidateRange(1, 10)]
        [int]$MaximumAttempts = 5
    )

    for ($attempt = 1; $attempt -le $MaximumAttempts; $attempt++) {
        try {
            $parameters = @{
                Method      = $Method
                Uri         = $Uri
                ErrorAction = 'Stop'
            }

            if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) {
                $parameters.Body = $Body
                $parameters.ContentType = 'application/json'
            }

            return Invoke-MgGraphRequest @parameters
        }
        catch {
            $message = Get-GraphErrorMessage -ErrorRecord $_
            $isTransient = $message -match '\b(429|500|502|503|504)\b'

            if (-not $isTransient -or $attempt -eq $MaximumAttempts) {
                throw
            }

            $delaySeconds = [math]::Min(60, [math]::Pow(2, $attempt))
            Write-Log -Level WARNING -Message "Transient Graph failure on attempt $attempt of $MaximumAttempts. Retrying in $delaySeconds second(s)."
            Start-Sleep -Seconds $delaySeconds
        }
    }
}

function Get-GraphCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Uri
    )

    $items = [System.Collections.Generic.List[object]]::new()
    $nextLink = $Uri
    $pageNumber = 0

    while (-not [string]::IsNullOrWhiteSpace($nextLink)) {
        $pageNumber++
        Write-Log -Message "Retrieving Microsoft Graph collection page $pageNumber."

        $response = Invoke-IntuneGraphRequest -Method GET -Uri $nextLink
        if ($null -eq $response) {
            throw "Microsoft Graph returned an empty response for URI: $nextLink"
        }

        $value = Get-ObjectMemberValue -InputObject $response -Name 'value'

        if ($null -ne $value) {
            $pageItems = @($value)
        }
        elseif ($response -is [System.Array] -or $response -is [System.Collections.IList]) {
            $pageItems = @($response)
        }
        else {
            $pageItems = @()
        }

        foreach ($item in $pageItems) {
            if ($null -ne $item) {
                $items.Add($item)
            }
        }

        Write-Log -Message "Page $pageNumber returned $($pageItems.Count) item(s)."
        $nextLinkValue = Get-ObjectMemberValue -InputObject $response -Name '@odata.nextLink'
        $nextLink = if ([string]::IsNullOrWhiteSpace([string]$nextLinkValue)) { $null } else { [string]$nextLinkValue }
    }

    Write-Log -Message "Microsoft Graph collection retrieval completed. Total items: $($items.Count)."
    return $items.ToArray()
}

function Connect-RequiredGraphSession {
    [CmdletBinding()]
    param()

    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
        Write-Log -Message 'Installing Microsoft.Graph.Authentication.'
        Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
    }

    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

    $useAppAuthentication = -not [string]::IsNullOrWhiteSpace($ClientId) -or
        -not [string]::IsNullOrWhiteSpace($CertificateThumbprint)

    if ($useAppAuthentication) {
        if ([string]::IsNullOrWhiteSpace($TenantId) -or
            [string]::IsNullOrWhiteSpace($ClientId) -or
            [string]::IsNullOrWhiteSpace($CertificateThumbprint)) {
            throw 'TenantId, ClientId, and CertificateThumbprint must all be provided for application authentication.'
        }

        Write-Log -Message "Connecting to Microsoft Graph using certificate-based application authentication for tenant $TenantId."
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $CertificateThumbprint -Environment $GraphEnvironment -NoWelcome -ErrorAction Stop
        return
    }

    $context = Get-MgContext
    $mustReconnect = $true

    if ($context) {
        $environmentMatches = [string]$context.Environment -eq $GraphEnvironment
        $tenantMatches = [string]::IsNullOrWhiteSpace($TenantId) -or [string]$context.TenantId -eq $TenantId
        $scopeMatches = $true

        foreach ($scope in $RequiredScopes) {
            if ($scope -notin @($context.Scopes)) {
                $scopeMatches = $false
            }
        }

        if ($environmentMatches -and $tenantMatches -and $scopeMatches) {
            $mustReconnect = $false
            Write-Log -Message "Using the existing Microsoft Graph connection for tenant $($context.TenantId)."
        }
    }

    if ($mustReconnect) {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        Write-Log -Message "Connecting interactively to Microsoft Graph with scopes: $($RequiredScopes -join ', ')."

        $connectParameters = @{
            Scopes      = $RequiredScopes
            Environment = $GraphEnvironment
            NoWelcome   = $true
            ErrorAction = 'Stop'
        }

        if (-not [string]::IsNullOrWhiteSpace($TenantId)) {
            $connectParameters.TenantId = $TenantId
        }

        Connect-MgGraph @connectParameters
    }
}

function Assert-ManagedGooglePlayBinding {
    [CmdletBinding()]
    param()

    Write-Log -Message 'Checking the Intune Managed Google Play connection.'
    $uri = "$GraphBetaBaseUri/deviceManagement/androidManagedStoreAccountEnterpriseSettings"
    $settings = Invoke-IntuneGraphRequest -Method GET -Uri $uri
    $bindStatus = [string](Get-ObjectMemberValue -InputObject $settings -Name 'bindStatus')

    if ([string]::IsNullOrWhiteSpace($bindStatus)) {
        $value = Get-ObjectMemberValue -InputObject $settings -Name 'value'
        if ($null -ne $value) {
            $settings = @($value) | Select-Object -First 1
            $bindStatus = [string](Get-ObjectMemberValue -InputObject $settings -Name 'bindStatus')
        }
    }

    if ($bindStatus -ne 'bound') {
        throw "Managed Google Play is not bound to this Intune tenant. Current bindStatus: '$bindStatus'. Connect Managed Google Play before running this script."
    }

    $lastSyncStatus = [string](Get-ObjectMemberValue -InputObject $settings -Name 'lastAppSyncStatus')
    $lastSyncDate = [string](Get-ObjectMemberValue -InputObject $settings -Name 'lastAppSyncDateTime')
    Write-Log -Level SUCCESS -Message "Managed Google Play is connected. Last sync status='$lastSyncStatus'; last sync='$lastSyncDate'."
}

function Get-AndroidManagedStoreApps {
    [CmdletBinding()]
    param()

    $uri = "$GraphBetaBaseUri/deviceAppManagement/mobileApps?`$filter=isof('microsoft.graph.androidManagedStoreApp')&`$top=100"
    return @(Get-GraphCollection -Uri $uri)
}

function Find-AndroidAppByPackageId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Apps,

        [Parameter(Mandatory)]
        [string]$PackageId
    )

    $matches = @(
        $Apps | Where-Object {
            $type = [string](Get-ObjectMemberValue -InputObject $_ -Name '@odata.type')
            $package = [string](Get-ObjectMemberValue -InputObject $_ -Name 'packageId')
            $identifier = [string](Get-ObjectMemberValue -InputObject $_ -Name 'appIdentifier')

            ($type -ieq '#microsoft.graph.androidManagedStoreApp' -or $type -ieq 'microsoft.graph.androidManagedStoreApp') -and
            ($package -ieq $PackageId -or $identifier -ieq $PackageId)
        }
    )

    return $matches
}

function Approve-ManagedGooglePlayApps {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$PackageIds
    )

    if ($PackageIds.Count -eq 0) {
        Write-Log -Message 'All catalog applications already exist in Intune. Managed Google Play approval is not required.'
        return
    }

    if ($SkipApproval) {
        Write-Log -Level WARNING -Message "Skipping Managed Google Play approval for $($PackageIds.Count) missing package(s) because -SkipApproval was specified."
        return
    }

    $uri = "$GraphBetaBaseUri/deviceManagement/androidManagedStoreAccountEnterpriseSettings/approveApps"
    $body = @{
        packageIds = $PackageIds
        approveAllPermissions = $true
    }

    try {
        Write-Log -Message "Approving $($PackageIds.Count) Managed Google Play app(s) and accepting current permissions."
        Invoke-IntuneGraphRequest -Method POST -Uri $uri -Body $body | Out-Null
        Write-Log -Level SUCCESS -Message 'Managed Google Play approval request completed.'
    }
    catch {
        $message = Get-GraphErrorMessage -ErrorRecord $_
        throw "Managed Google Play approval failed. The approveApps action may require certificate-based application authentication with DeviceManagementConfiguration.ReadWrite.All. Error: $message"
    }
}

function Start-ManagedGooglePlaySync {
    [CmdletBinding()]
    param()

    $uri = "$GraphBetaBaseUri/deviceManagement/androidManagedStoreAccountEnterpriseSettings/syncApps"
    Write-Log -Message 'Starting Managed Google Play application synchronization.'
    Invoke-IntuneGraphRequest -Method POST -Uri $uri | Out-Null
    Write-Log -Level SUCCESS -Message 'Managed Google Play synchronization request submitted.'
}

function Set-AllLicensedUsersAndroidAssignment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppId,

        [Parameter(Mandatory)]
        [ValidateSet('required', 'available')]
        [string]$Intent,

        [Parameter(Mandatory)]
        [ValidateSet('default', 'postponed', 'priority')]
        [string]$UpdateMode
    )

    $assignmentsUri = "$GraphBetaBaseUri/deviceAppManagement/mobileApps/$AppId/assignments"
    $assignments = @(Get-GraphCollection -Uri $assignmentsUri)

    $matchingAssignments = @(
        $assignments | Where-Object {
            $target = Get-ObjectMemberValue -InputObject $_ -Name 'target'
            $targetType = [string](Get-ObjectMemberValue -InputObject $target -Name '@odata.type')
            $targetType -match 'allLicensedUsersAssignmentTarget$'
        }
    )

    $correctAssignment = $null

    foreach ($assignment in $matchingAssignments) {
        $existingIntent = [string](Get-ObjectMemberValue -InputObject $assignment -Name 'intent')
        $settings = Get-ObjectMemberValue -InputObject $assignment -Name 'settings'
        $existingMode = [string](Get-ObjectMemberValue -InputObject $settings -Name 'autoUpdateMode')

        if ($existingIntent -eq $Intent -and $existingMode -eq $UpdateMode -and $null -eq $correctAssignment) {
            $correctAssignment = $assignment
        }
    }

    if ($null -ne $correctAssignment) {
        Write-Log -Level SUCCESS -Message "All Licensed Users assignment already has intent '$Intent' and auto update mode '$UpdateMode' for application $AppId."

        foreach ($duplicate in $matchingAssignments) {
            $duplicateId = [string](Get-ObjectMemberValue -InputObject $duplicate -Name 'id')
            $correctId = [string](Get-ObjectMemberValue -InputObject $correctAssignment -Name 'id')

            if (-not [string]::IsNullOrWhiteSpace($duplicateId) -and $duplicateId -ne $correctId) {
                Invoke-IntuneGraphRequest -Method DELETE -Uri "$assignmentsUri/$duplicateId" | Out-Null
                Write-Log -Level WARNING -Message "Removed duplicate All Licensed Users assignment $duplicateId from application $AppId."
            }
        }
        return
    }

    foreach ($existingAssignment in $matchingAssignments) {
        $assignmentId = [string](Get-ObjectMemberValue -InputObject $existingAssignment -Name 'id')
        if (-not [string]::IsNullOrWhiteSpace($assignmentId)) {
            Invoke-IntuneGraphRequest -Method DELETE -Uri "$assignmentsUri/$assignmentId" | Out-Null
            Write-Log -Level WARNING -Message "Removed existing All Licensed Users assignment $assignmentId so the desired Android assignment settings can be applied."
        }
    }

    $assignmentBody = @{
        '@odata.type' = '#microsoft.graph.mobileAppAssignment'
        intent = $Intent
        target = @{
            '@odata.type' = '#microsoft.graph.allLicensedUsersAssignmentTarget'
        }
        settings = @{
            '@odata.type' = '#microsoft.graph.androidManagedStoreAppAssignmentSettings'
            androidManagedStoreAppTrackIds = @()
            autoUpdateMode = $UpdateMode
        }
    }

    Invoke-IntuneGraphRequest -Method POST -Uri $assignmentsUri -Body $assignmentBody | Out-Null
    Write-Log -Level SUCCESS -Message "Created All Licensed Users assignment with intent '$Intent' and auto update mode '$UpdateMode' for application $AppId."
}

$AppsToDeploy = @(
    @{ Name = 'Microsoft Outlook';                  PackageId = 'com.microsoft.office.outlook';          Intent = 'required'  },
    @{ Name = 'Keeper Password Manager';            PackageId = 'com.callpod.android_apps.keeper';       Intent = 'required'  },
    @{ Name = 'Adobe Acrobat Reader: Edit PDF';     PackageId = 'com.adobe.reader';                       Intent = 'available' },
    @{ Name = 'Duo Mobile';                         PackageId = 'com.duosecurity.duomobile';              Intent = 'available' },
    @{ Name = 'Firefox Fast & Private Browser';     PackageId = 'org.mozilla.firefox';                    Intent = 'available' },
    @{ Name = 'Google Chrome';                      PackageId = 'com.android.chrome';                     Intent = 'available' },
    @{ Name = 'Intune Company Portal';              PackageId = 'com.microsoft.windowsintune.companyportal'; Intent = 'available' },
    @{ Name = 'Microsoft Authenticator';            PackageId = 'com.azure.authenticator';               Intent = 'available' },
    @{ Name = 'Microsoft Edge: Web Browser';        PackageId = 'com.microsoft.emmx';                     Intent = 'available' },
    @{ Name = 'Microsoft Excel';                    PackageId = 'com.microsoft.office.excel';             Intent = 'available' },
    @{ Name = 'Microsoft OneDrive';                 PackageId = 'com.microsoft.skydrive';                 Intent = 'available' },
    @{ Name = 'Microsoft OneNote';                  PackageId = 'com.microsoft.office.onenote';           Intent = 'available' },
    @{ Name = 'Microsoft PowerPoint';               PackageId = 'com.microsoft.office.powerpoint';        Intent = 'available' },
    @{ Name = 'Microsoft SharePoint';               PackageId = 'com.microsoft.sharepoint';               Intent = 'available' },
    @{ Name = 'Microsoft Teams';                    PackageId = 'com.microsoft.teams';                    Intent = 'available' },
    @{ Name = 'Microsoft To Do';                    PackageId = 'com.microsoft.todos';                    Intent = 'available' },
    @{ Name = 'Microsoft Word';                     PackageId = 'com.microsoft.office.word';              Intent = 'available' },
    @{ Name = 'Zoom Workplace';                     PackageId = 'us.zoom.videomeetings';                  Intent = 'available' }
)

try {
    Write-Log -Message "Starting Intune Android Enterprise work profile app deployment script version $ScriptVersion."
    Write-Log -Message "Cloud: $CloudLabel"
    Write-Log -Message "Log file: $LogFile"
    Write-Log -Message "CSV results file: $CsvFile"

    Connect-RequiredGraphSession
    Assert-ManagedGooglePlayBinding

    Write-Log -Message 'Retrieving existing Android Managed Google Play apps from Intune.'
    $existingApps = @(Get-AndroidManagedStoreApps)

    $missingPackageIds = [System.Collections.Generic.List[string]]::new()

    foreach ($catalogApp in $AppsToDeploy) {
        $matches = @(Find-AndroidAppByPackageId -Apps $existingApps -PackageId $catalogApp.PackageId)

        if ($matches.Count -eq 0) {
            $missingPackageIds.Add($catalogApp.PackageId)
            Write-Log -Message "$($catalogApp.Name) is not currently synchronized into Intune. Package ID: $($catalogApp.PackageId)."
        }
        elseif ($matches.Count -gt 1) {
            $ids = @($matches | ForEach-Object { Get-ObjectMemberValue -InputObject $_ -Name 'id' }) -join ', '
            Write-Log -Level WARNING -Message "Found $($matches.Count) existing Intune app objects for $($catalogApp.Name). IDs: $ids. The first published match will be used; no new app object will be created."
        }
        else {
            Write-Log -Message "$($catalogApp.Name) already exists in Intune. Approval and creation will be skipped."
        }
    }

    Approve-ManagedGooglePlayApps -PackageIds $missingPackageIds.ToArray()
    Start-ManagedGooglePlaySync

    Write-Log -Message 'Waiting for all catalog applications to appear as published Android Managed Google Play apps in Intune.'
    $deadline = (Get-Date).AddSeconds($SyncTimeoutSeconds)
    $resolvedApps = @{}
    $cycle = 0

    do {
        $cycle++
        Write-Log -Message "Managed Google Play discovery cycle $cycle."
        $existingApps = @(Get-AndroidManagedStoreApps)

        foreach ($catalogApp in $AppsToDeploy) {
            if ($resolvedApps.ContainsKey($catalogApp.PackageId)) {
                continue
            }

            $matches = @(Find-AndroidAppByPackageId -Apps $existingApps -PackageId $catalogApp.PackageId)
            if ($matches.Count -eq 0) {
                Write-Log -Message "$($catalogApp.Name) has not synchronized into Intune yet."
                continue
            }

            $selected = $matches |
                Sort-Object -Property @{ Expression = {
                    $state = [string](Get-ObjectMemberValue -InputObject $_ -Name 'publishingState')
                    if ($state -eq 'published') { 0 } else { 1 }
                } }, @{ Expression = {
                    [datetime](Get-ObjectMemberValue -InputObject $_ -Name 'createdDateTime')
                } } |
                Select-Object -First 1

            $state = [string](Get-ObjectMemberValue -InputObject $selected -Name 'publishingState')
            $appId = [string](Get-ObjectMemberValue -InputObject $selected -Name 'id')

            if ($state -eq 'published' -and -not [string]::IsNullOrWhiteSpace($appId)) {
                $resolvedApps[$catalogApp.PackageId] = $selected
                Write-Log -Level SUCCESS -Message "$($catalogApp.Name) is published in Intune with ID $appId."
            }
            else {
                Write-Log -Message "$($catalogApp.Name) publishing state is '$state'."
            }
        }

        if ($resolvedApps.Count -lt $AppsToDeploy.Count -and (Get-Date) -lt $deadline) {
            Write-Log -Message "Waiting $PollIntervalSeconds second(s) before the next discovery cycle."
            Start-Sleep -Seconds $PollIntervalSeconds
        }
    }
    while ($resolvedApps.Count -lt $AppsToDeploy.Count -and (Get-Date) -lt $deadline)

    foreach ($catalogApp in $AppsToDeploy) {
        if (-not $resolvedApps.ContainsKey($catalogApp.PackageId)) {
            $message = "The app did not become available and published in Intune within $SyncTimeoutSeconds seconds. Confirm that the package is approved in Managed Google Play and run the script again."
            Write-Log -Level ERROR -Message "$($catalogApp.Name): $message"
            $Results.Add([pscustomobject]@{
                Application = $catalogApp.Name
                PackageId   = $catalogApp.PackageId
                Intent      = $catalogApp.Intent
                Action      = 'Approve, sync, and assign'
                Status      = 'Failed'
                AppId       = $null
                Error       = $message
            })
            continue
        }

        $app = $resolvedApps[$catalogApp.PackageId]
        $appId = [string](Get-ObjectMemberValue -InputObject $app -Name 'id')

        try {
            Write-Log -Message "Applying '$($catalogApp.Intent)' assignment to $($catalogApp.Name)."
            Set-AllLicensedUsersAndroidAssignment -AppId $appId -Intent $catalogApp.Intent -UpdateMode $AutoUpdateMode

            $Results.Add([pscustomobject]@{
                Application = $catalogApp.Name
                PackageId   = $catalogApp.PackageId
                Intent      = $catalogApp.Intent
                Action      = 'Approved/synchronized and assigned'
                Status      = 'Success'
                AppId       = $appId
                Error       = $null
            })
        }
        catch {
            $message = Get-GraphErrorMessage -ErrorRecord $_
            Write-Log -Level ERROR -Message "Failed to assign $($catalogApp.Name). $message"

            $Results.Add([pscustomobject]@{
                Application = $catalogApp.Name
                PackageId   = $catalogApp.PackageId
                Intent      = $catalogApp.Intent
                Action      = 'Assign existing Managed Google Play app'
                Status      = 'Failed'
                AppId       = $appId
                Error       = $message
            })
        }
    }
}
catch {
    $fatalMessage = Get-GraphErrorMessage -ErrorRecord $_
    Write-Log -Level ERROR -Message "Fatal script failure. $fatalMessage"

    $Results.Add([pscustomobject]@{
        Application = 'Script execution'
        PackageId   = $null
        Intent      = $null
        Action      = 'Fatal error'
        Status      = 'Failed'
        AppId       = $null
        Error       = $fatalMessage
    })
}
finally {
    if ($Results.Count -gt 0) {
        $Results | Export-Csv -LiteralPath $CsvFile -NoTypeInformation -Encoding UTF8
    }

    Write-Host ''
    Write-Host 'Intune Android Enterprise Application Deployment Results' -ForegroundColor Cyan
    $Results | Format-Table Application, Intent, Action, Status, AppId -AutoSize

    $successCount = @($Results | Where-Object Status -eq 'Success').Count
    $failureCount = @($Results | Where-Object Status -eq 'Failed').Count

    Write-Log -Message "Successful applications: $successCount"

    if ($failureCount -gt 0) {
        Write-Log -Level ERROR -Message "Failed applications: $failureCount"
        Write-Log -Level ERROR -Message "Review the log file at $LogFile and CSV file at $CsvFile."
        exit 1
    }

    Write-Log -Level SUCCESS -Message 'All Android Enterprise work profile applications completed successfully.'
    exit 0
}
