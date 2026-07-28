<#
.SYNOPSIS
    Creates and assigns iOS App Store applications in Microsoft Intune by using Microsoft Graph.

.DESCRIPTION
    Creates missing iOS App Store application objects in Microsoft Intune and configures an
    assignment to All Licensed Users. Existing unrelated assignments are preserved.

    The script is designed to be safely re-run. It performs the following actions:
      - Installs and imports Microsoft.Graph.Authentication when needed.
      - Connects to Microsoft Graph with DeviceManagementApps.ReadWrite.All.
      - Validates every App Store ID and bundle ID against Apple before changing Intune.
      - Retrieves the current App Store URL, publisher, minimum OS, and supported device families.
      - Retrieves all existing Intune mobile applications with pagination support.
      - Finds existing iOS Store apps by App Store ID, bundle ID, notes, or display name.
      - Detects duplicate existing app objects and reuses one instead of creating another.
      - Creates missing applications and can optionally refresh supported mutable metadata on existing applications.
      - Waits for newly created applications to reach the published state.
      - Creates the All Licensed Users assignment through Microsoft Graph beta.
      - Recreates only the matching All Licensed Users assignment when its settings are incorrect.
      - Sets Prevent iCloud app backup to Yes on every managed app assignment.
      - Preserves unrelated assignments.
      - Retries transient Microsoft Graph failures.
      - Writes a detailed log and CSV results file to C:\Temp.

.NOTES
    Script name: Intune-Configure-iOS-Apps-Microsoft-Graph-PowerShell-GCCH.ps1
    Version:     1.10.1-GCCH
    Author:      Resilient IT

    Required delegated Microsoft Graph permission:
        DeviceManagementApps.ReadWrite.All

    This script uses interactive delegated authentication against Microsoft 365 GCC High.
    GCC High uses the USGov Microsoft Graph environment and graph.microsoft.us endpoints.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$LogDirectory = 'C:\Temp',

    [Parameter()]
    [ValidateRange(30, 1800)]
    [int]$PublishTimeoutSeconds = 600,

    [Parameter()]
    [ValidateRange(2, 60)]
    [int]$PublishPollIntervalSeconds = 10,

    [Parameter()]
    [ValidatePattern('^[A-Za-z]{2}$')]
    [string]$AppleStoreCountry = 'us',

    [Parameter()]
    [bool]$UpdateExistingAppMetadata = $false,

    [Parameter()]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$TenantId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptVersion = '1.10.1-GCCH'
$GraphEnvironment = 'USGov'
$GraphBaseUri = 'https://graph.microsoft.us/v1.0'
$GraphBetaBaseUri = 'https://graph.microsoft.us/beta'
$RequiredGraphScope = 'DeviceManagementApps.ReadWrite.All'
$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

if (-not (Test-Path -LiteralPath $LogDirectory)) {
    New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
}

$LogPath = Join-Path -Path $LogDirectory -ChildPath "Intune-iOS-App-Deployment-GCCH-$Timestamp.log"
$CsvPath = Join-Path -Path $LogDirectory -ChildPath "Intune-iOS-App-Deployment-GCCH-$Timestamp.csv"

#region Functions

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter()]
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $time = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "$time [$Level] $Message"

    try {
        Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    }
    catch {
        Write-Warning "Unable to write to log file '$LogPath'. $($_.Exception.Message)"
    }

    $color = switch ($Level) {
        'SUCCESS' { 'Green' }
        'WARNING' { 'Yellow' }
        'ERROR'   { 'Red' }
        default   { 'Cyan' }
    }

    Write-Host "[$Level] $Message" -ForegroundColor $color
}


function Get-ObjectMemberValue {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) {
            return $InputObject[$Name]
        }

        foreach ($key in $InputObject.Keys) {
            if ([string]$key -ieq $Name) {
                return $InputObject[$key]
            }
        }

        return $null
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -ne $property) {
        return $property.Value
    }

    return $null
}


function Invoke-AppleLookupRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Uri,

        [Parameter()]
        [ValidateRange(1, 5)]
        [int]$MaximumAttempts = 3
    )

    for ($attempt = 1; $attempt -le $MaximumAttempts; $attempt++) {
        try {
            return Invoke-RestMethod -Method Get -Uri $Uri -UseBasicParsing -ErrorAction Stop
        }
        catch {
            if ($attempt -eq $MaximumAttempts) {
                throw
            }

            $delaySeconds = [math]::Min(15, [math]::Pow(2, $attempt))
            Write-Log -Level WARNING -Message "Apple App Store lookup attempt $attempt of $MaximumAttempts failed. Retrying in $delaySeconds second(s). $($_.Exception.Message)"
            Start-Sleep -Seconds $delaySeconds
        }
    }
}

function ConvertTo-IntuneMinimumOperatingSystem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$MinimumOsVersion,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ApplicationName
    )

    $majorVersion = 0
    $versionMatch = [regex]::Match($MinimumOsVersion, '^(?<Major>\d+)')
    if (-not $versionMatch.Success -or -not [int]::TryParse($versionMatch.Groups['Major'].Value, [ref]$majorVersion)) {
        throw "Apple returned an invalid minimum OS version '$MinimumOsVersion' for '$ApplicationName'."
    }

    if ($majorVersion -lt 8) {
        Write-Log -Level WARNING -Message "$ApplicationName reports minimum iOS $MinimumOsVersion. Microsoft Graph v1.0 starts at iOS 8.0, so v8_0 will be used."
        $majorVersion = 8
    }
    elseif ($majorVersion -gt 15) {
        Write-Log -Level WARNING -Message "$ApplicationName reports minimum iOS $MinimumOsVersion. Microsoft Graph v1.0 currently exposes minimum-OS flags only through v15_0, so v15_0 will be used. Apple will still enforce the app's actual minimum OS."
        $majorVersion = 15
    }

    $minimumOs = @{
        '@odata.type' = '#microsoft.graph.iosMinimumOperatingSystem'
        v8_0 = $false
        v9_0 = $false
        v10_0 = $false
        v11_0 = $false
        v12_0 = $false
        v13_0 = $false
        v14_0 = $false
        v15_0 = $false
    }

    $minimumOs["v${majorVersion}_0"] = $true
    return $minimumOs
}

function Get-AppleApplicableDeviceType {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object[]]$SupportedDevices,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ApplicationName
    )

    $deviceValues = @($SupportedDevices | ForEach-Object { [string]$_ })
    $supportsIpad = @($deviceValues | Where-Object { $_ -match '^iPad' }).Count -gt 0
    $supportsIphoneOrIpod = @($deviceValues | Where-Object { $_ -match '^(iPhone|iPod)' }).Count -gt 0

    if (-not $supportsIpad -and -not $supportsIphoneOrIpod) {
        Write-Log -Level WARNING -Message "Apple did not return recognizable iPhone/iPod/iPad device families for $ApplicationName. Both Intune device types will be enabled."
        $supportsIpad = $true
        $supportsIphoneOrIpod = $true
    }

    return @{
        '@odata.type' = '#microsoft.graph.iosDeviceType'
        iPad = $supportsIpad
        iPhoneAndIPod = $supportsIphoneOrIpod
    }
}

function Get-ValidatedAppleCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object[]]$Catalog,

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z]{2}$')]
        [string]$Country
    )

    $normalizedCountry = $Country.ToLowerInvariant()
    $ids = @(
        $Catalog | ForEach-Object {
            ([string]$_.AppStoreId) -replace '^id', ''
        }
    )

    $lookupUri = "https://itunes.apple.com/lookup?id=$([string]::Join(',', $ids))&country=$normalizedCountry&entity=software"
    Write-Log -Message "Querying Apple App Store metadata for $($ids.Count) application(s) in storefront '$normalizedCountry'."
    $response = Invoke-AppleLookupRequest -Uri $lookupUri

    $appleResults = @()
    if ($null -ne $response) {
        $resultsValue = Get-ObjectMemberValue -InputObject $response -Name 'results'
        if ($null -ne $resultsValue) {
            $appleResults = @($resultsValue)
        }
    }

    $validated = [System.Collections.Generic.List[object]]::new()
    $validationErrors = [System.Collections.Generic.List[string]]::new()

    foreach ($catalogItem in $Catalog) {
        $configuredName = [string]$catalogItem.Name
        $expectedBundleId = [string]$catalogItem.BundleId
        $appStoreId = (([string]$catalogItem.AppStoreId) -replace '^id', '')
        $intent = [string]$catalogItem.Intent

        $appleApp = $appleResults |
            Where-Object { [string](Get-ObjectMemberValue -InputObject $_ -Name 'trackId') -eq $appStoreId } |
            Select-Object -First 1

        if ($null -eq $appleApp) {
            $validationErrors.Add("${configuredName}: Apple returned no software result for App Store ID $appStoreId in storefront '$normalizedCountry'.")
            continue
        }

        $actualBundleId = [string](Get-ObjectMemberValue -InputObject $appleApp -Name 'bundleId')
        if ([string]::IsNullOrWhiteSpace($actualBundleId)) {
            $validationErrors.Add("${configuredName}: Apple did not return a bundle ID for App Store ID $appStoreId.")
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($expectedBundleId) -and $actualBundleId -ne $expectedBundleId) {
            Write-Log -Level WARNING -Message "${configuredName}: configured bundle ID '$expectedBundleId' differs from Apple's current bundle ID '$actualBundleId'. Apple's value will be used."
        }

        $appStoreUrl = [string](Get-ObjectMemberValue -InputObject $appleApp -Name 'trackViewUrl')
        if ([string]::IsNullOrWhiteSpace($appStoreUrl)) {
            $validationErrors.Add("${configuredName}: Apple did not return trackViewUrl for App Store ID $appStoreId.")
            continue
        }

        $priceValue = Get-ObjectMemberValue -InputObject $appleApp -Name 'price'
        $price = 0.0
        if ($null -ne $priceValue -and [double]::TryParse([string]$priceValue, [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$price)) {
            if ($price -gt 0) {
                $validationErrors.Add("${configuredName}: Apple reports a price of $price. Intune iOS Store app assignments through this method are intended for free apps.")
                continue
            }
        }

        $minimumOsVersion = [string](Get-ObjectMemberValue -InputObject $appleApp -Name 'minimumOsVersion')
        if ([string]::IsNullOrWhiteSpace($minimumOsVersion)) {
            $validationErrors.Add("${configuredName}: Apple did not return minimumOsVersion for App Store ID $appStoreId.")
            continue
        }

        try {
            $minimumOperatingSystem = ConvertTo-IntuneMinimumOperatingSystem -MinimumOsVersion $minimumOsVersion -ApplicationName $configuredName
            $supportedDevices = @(Get-ObjectMemberValue -InputObject $appleApp -Name 'supportedDevices')
            $applicableDeviceType = Get-AppleApplicableDeviceType -SupportedDevices $supportedDevices -ApplicationName $configuredName
        }
        catch {
            $validationErrors.Add("${configuredName}: $($_.Exception.Message)")
            continue
        }

        $publisher = [string](Get-ObjectMemberValue -InputObject $appleApp -Name 'sellerName')
        if ([string]::IsNullOrWhiteSpace($publisher)) {
            $publisher = [string](Get-ObjectMemberValue -InputObject $appleApp -Name 'artistName')
        }
        if ([string]::IsNullOrWhiteSpace($publisher)) {
            $publisher = 'App Store'
        }

        $appleName = [string](Get-ObjectMemberValue -InputObject $appleApp -Name 'trackName')
        $version = [string](Get-ObjectMemberValue -InputObject $appleApp -Name 'version')

        Write-Log -Level SUCCESS -Message "Validated $configuredName. Apple name='$appleName'; bundleId='$actualBundleId'; minimumOS='$minimumOsVersion'; URL='$appStoreUrl'."

        $validated.Add([pscustomobject]@{
            Name = $configuredName
            AppleName = $appleName
            BundleId = $actualBundleId
            AppStoreId = $appStoreId
            AppStoreUrl = $appStoreUrl
            Intent = $intent
            Publisher = $publisher
            Developer = $publisher
            Version = $version
            AppleMinimumOsVersion = $minimumOsVersion
            ApplicableDeviceType = $applicableDeviceType
            MinimumSupportedOperatingSystem = $minimumOperatingSystem
        })
    }

    if ($validationErrors.Count -gt 0) {
        foreach ($validationError in $validationErrors) {
            Write-Log -Level ERROR -Message $validationError
        }
        throw "Apple App Store validation failed for $($validationErrors.Count) application(s). No Intune application objects were created or updated."
    }

    Write-Log -Level SUCCESS -Message "Apple App Store validation completed successfully for all $($validated.Count) application(s)."
    return @($validated.ToArray())
}

function New-IosStoreAppPayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$AppMetadata
    )

    return @{
        '@odata.type' = '#microsoft.graph.iosStoreApp'
        displayName = [string]$AppMetadata.Name
        publisher = [string]$AppMetadata.Publisher
        description = "$($AppMetadata.Name) deployed by Resilient IT automation. Apple App Store metadata validated at deployment time."
        bundleId = [string]$AppMetadata.BundleId
        appStoreUrl = [string]$AppMetadata.AppStoreUrl
        applicableDeviceType = $AppMetadata.ApplicableDeviceType
        minimumSupportedOperatingSystem = $AppMetadata.MinimumSupportedOperatingSystem
        isFeatured = $false
        owner = 'Resilient IT'
        developer = [string]$AppMetadata.Developer
        notes = "Created or maintained through Microsoft Graph automation. Apple App Store ID: $($AppMetadata.AppStoreId). Apple version at validation: $($AppMetadata.Version)."
    }
}

function New-IosStoreAppUpdatePayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$AppMetadata
    )

    # Intune's current backend rejects AppStoreUrl during PATCH even though it
    # is present in the public Graph schema. BundleId is also treated as an
    # identity value and is intentionally excluded from updates.
    return @{
        '@odata.type' = '#microsoft.graph.iosStoreApp'
        displayName = [string]$AppMetadata.Name
        publisher = [string]$AppMetadata.Publisher
        description = "$($AppMetadata.Name) deployed by Resilient IT automation. Apple App Store metadata validated at deployment time."
        applicableDeviceType = $AppMetadata.ApplicableDeviceType
        minimumSupportedOperatingSystem = $AppMetadata.MinimumSupportedOperatingSystem
        isFeatured = $false
        owner = 'Resilient IT'
        developer = [string]$AppMetadata.Developer
        notes = "Maintained through Microsoft Graph automation. Apple App Store ID: $($AppMetadata.AppStoreId). Apple version at validation: $($AppMetadata.Version)."
    }
}

function Test-IosStoreAppMetadataDrift {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$ExistingApp,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$DesiredMetadata
    )

    # appStoreUrl and bundleId are intentionally not evaluated for PATCH.
    # The live Intune service rejects appStoreUrl updates and bundleId is an
    # application identity value. Apple validation is still logged separately.
    $currentPublisher = [string](Get-ObjectMemberValue -InputObject $ExistingApp -Name 'publisher')
    if ($currentPublisher -ne [string]$DesiredMetadata.Publisher) { return $true }

    $currentDeviceType = Get-ObjectMemberValue -InputObject $ExistingApp -Name 'applicableDeviceType'
    $currentIpad = [bool](Get-ObjectMemberValue -InputObject $currentDeviceType -Name 'iPad')
    $currentIphone = [bool](Get-ObjectMemberValue -InputObject $currentDeviceType -Name 'iPhoneAndIPod')
    if ($currentIpad -ne [bool]$DesiredMetadata.ApplicableDeviceType.iPad) { return $true }
    if ($currentIphone -ne [bool]$DesiredMetadata.ApplicableDeviceType.iPhoneAndIPod) { return $true }

    $currentMinimumOs = Get-ObjectMemberValue -InputObject $ExistingApp -Name 'minimumSupportedOperatingSystem'
    foreach ($key in @('v8_0','v9_0','v10_0','v11_0','v12_0','v13_0','v14_0','v15_0')) {
        $currentValue = [bool](Get-ObjectMemberValue -InputObject $currentMinimumOs -Name $key)
        $desiredValue = [bool]$DesiredMetadata.MinimumSupportedOperatingSystem[$key]
        if ($currentValue -ne $desiredValue) { return $true }
    }

    return $false
}

function Get-GraphErrorMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    if ($null -ne $ErrorRecord.ErrorDetails -and
        -not [string]::IsNullOrWhiteSpace($ErrorRecord.ErrorDetails.Message)) {
        return $ErrorRecord.ErrorDetails.Message
    }

    if ($null -ne $ErrorRecord.Exception -and
        -not [string]::IsNullOrWhiteSpace($ErrorRecord.Exception.Message)) {
        return $ErrorRecord.Exception.Message
    }

    return [string]$ErrorRecord
}

function Get-HttpStatusCodeFromError {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $statusCode = $null

    try {
        $responseProperty = $ErrorRecord.Exception.PSObject.Properties['Response']
        if ($null -ne $responseProperty -and $null -ne $responseProperty.Value) {
            $statusCodeProperty = $responseProperty.Value.PSObject.Properties['StatusCode']
            if ($null -ne $statusCodeProperty -and $null -ne $statusCodeProperty.Value) {
                $statusCode = [int]$statusCodeProperty.Value
            }
        }
    }
    catch {
        $statusCode = $null
    }

    if ($null -eq $statusCode) {
        $message = Get-GraphErrorMessage -ErrorRecord $ErrorRecord
        if ($message -match '\b(429|500|502|503|504)\b') {
            $statusCode = [int]$Matches[1]
        }
    }

    return $statusCode
}

function Get-RetryAfterSeconds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,

        [Parameter(Mandatory)]
        [ValidateRange(1, 10)]
        [int]$Attempt
    )

    $retryAfter = $null

    try {
        $responseProperty = $ErrorRecord.Exception.PSObject.Properties['Response']
        if ($null -ne $responseProperty -and $null -ne $responseProperty.Value) {
            $headersProperty = $responseProperty.Value.PSObject.Properties['Headers']
            if ($null -ne $headersProperty -and $null -ne $headersProperty.Value) {
                $headers = $headersProperty.Value
                $retryAfterHeader = $headers.PSObject.Properties['Retry-After']
                if ($null -ne $retryAfterHeader -and $null -ne $retryAfterHeader.Value) {
                    $rawValue = [string]$retryAfterHeader.Value
                    $parsedValue = 0
                    if ([int]::TryParse($rawValue, [ref]$parsedValue)) {
                        $retryAfter = $parsedValue
                    }
                }
            }
        }
    }
    catch {
        $retryAfter = $null
    }

    if ($null -eq $retryAfter -or $retryAfter -lt 1) {
        $retryAfter = [math]::Min(60, [math]::Pow(2, $Attempt))
    }

    return [int]$retryAfter
}

function Invoke-IntuneGraphRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PATCH', 'DELETE')]
        [string]$Method,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
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
                $parameters['Body'] = $Body
                $parameters['ContentType'] = 'application/json'
            }

            return Invoke-MgGraphRequest @parameters
        }
        catch {
            $statusCode = Get-HttpStatusCodeFromError -ErrorRecord $_
            $message = Get-GraphErrorMessage -ErrorRecord $_
            $isTransient = $statusCode -in @(429, 500, 502, 503, 504)

            if (-not $isTransient -or $attempt -eq $MaximumAttempts) {
                throw
            }

            $delaySeconds = Get-RetryAfterSeconds -ErrorRecord $_ -Attempt $attempt
            Write-Log -Level WARNING -Message "Microsoft Graph request failed with transient status $statusCode. Attempt $attempt of $MaximumAttempts. Retrying in $delaySeconds second(s). Details: $message"
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

        $pageItems = @()
        $value = Get-ObjectMemberValue -InputObject $response -Name 'value'

        if ($null -ne $value) {
            $pageItems = @($value)
        }
        elseif ($response -is [System.Array] -or $response -is [System.Collections.IList]) {
            $pageItems = @($response)
        }
        elseif ($response -is [System.Collections.IDictionary]) {
            $looksLikeSingleResource = $null -ne (Get-ObjectMemberValue -InputObject $response -Name 'id')
            if ($looksLikeSingleResource) {
                $pageItems = @($response)
            }
        }

        foreach ($item in $pageItems) {
            if ($null -ne $item) {
                $items.Add($item)
            }
        }

        Write-Log -Message "Page $pageNumber returned $($pageItems.Count) item(s)."

        $nextLinkValue = Get-ObjectMemberValue -InputObject $response -Name '@odata.nextLink'
        if (-not [string]::IsNullOrWhiteSpace([string]$nextLinkValue)) {
            $nextLink = [string]$nextLinkValue
        }
        else {
            $nextLink = $null
        }
    }

    Write-Log -Message "Microsoft Graph collection retrieval completed. Total items: $($items.Count)."
    return @($items.ToArray())
}

function Wait-IntuneAppPublished {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$AppId,

        [Parameter(Mandatory)]
        [ValidateRange(30, 1800)]
        [int]$TimeoutSeconds,

        [Parameter(Mandatory)]
        [ValidateRange(2, 60)]
        [int]$PollIntervalSeconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $uri = "$GraphBaseUri/deviceAppManagement/mobileApps/$AppId"

    do {
        $app = Invoke-IntuneGraphRequest -Method GET -Uri $uri
        $publishingState = [string](Get-ObjectMemberValue -InputObject $app -Name 'publishingState')

        switch ($publishingState) {
            'published' {
                Write-Log -Level SUCCESS -Message "Application $AppId is published."
                return $app
            }

            'notPublished' {
                throw "The Intune application $AppId entered the notPublished state."
            }

            default {
                $displayState = if ([string]::IsNullOrWhiteSpace($publishingState)) { 'unknown' } else { $publishingState }
                Write-Log -Message "Application $AppId publishing state is '$displayState'. Waiting $PollIntervalSeconds second(s)."
                Start-Sleep -Seconds $PollIntervalSeconds
            }
        }
    }
    while ((Get-Date) -lt $deadline)

    throw "Application $AppId did not reach the published state within $TimeoutSeconds seconds."
}

function Get-ExistingIosStoreApp {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$MobileApps = @(),

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$BundleId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$AppStoreId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DisplayName
    )

    $normalizedStoreId = ($AppStoreId -replace '^id', '').Trim()
    $candidates = [System.Collections.Generic.List[object]]::new()

    foreach ($mobileApp in @($MobileApps)) {
        $odataType = [string](Get-ObjectMemberValue -InputObject $mobileApp -Name '@odata.type')
        if ($odataType -ne '#microsoft.graph.iosStoreApp') {
            continue
        }

        $existingId = [string](Get-ObjectMemberValue -InputObject $mobileApp -Name 'id')
        if ([string]::IsNullOrWhiteSpace($existingId)) {
            continue
        }

        $existingBundleId = [string](Get-ObjectMemberValue -InputObject $mobileApp -Name 'bundleId')
        $existingDisplayName = [string](Get-ObjectMemberValue -InputObject $mobileApp -Name 'displayName')
        $existingStoreUrl = [string](Get-ObjectMemberValue -InputObject $mobileApp -Name 'appStoreUrl')
        $existingNotes = [string](Get-ObjectMemberValue -InputObject $mobileApp -Name 'notes')
        $publishingState = [string](Get-ObjectMemberValue -InputObject $mobileApp -Name 'publishingState')

        $reasons = [System.Collections.Generic.List[string]]::new()
        $score = 0

        if (-not [string]::IsNullOrWhiteSpace($existingStoreUrl) -and
            $existingStoreUrl -match "(?i)/id$([regex]::Escape($normalizedStoreId))(?:[/?#]|$)") {
            $reasons.Add('App Store ID in URL')
            $score += 100
        }

        if (-not [string]::IsNullOrWhiteSpace($existingNotes) -and
            $existingNotes -match "(?i)Apple App Store ID\s*:\s*$([regex]::Escape($normalizedStoreId))(?:\D|$)") {
            $reasons.Add('App Store ID in notes')
            $score += 90
        }

        if (-not [string]::IsNullOrWhiteSpace($existingBundleId) -and
            $existingBundleId -ieq $BundleId) {
            $reasons.Add('Bundle ID')
            $score += 80
        }

        if (-not [string]::IsNullOrWhiteSpace($existingDisplayName) -and
            $existingDisplayName -ieq $DisplayName) {
            $reasons.Add('Display name')
            $score += 20
        }

        if ($score -le 0) {
            continue
        }

        if ($publishingState -eq 'published') {
            $score += 5
        }

        $candidates.Add([pscustomobject]@{
            App = $mobileApp
            Id = $existingId
            DisplayName = $existingDisplayName
            BundleId = $existingBundleId
            AppStoreUrl = $existingStoreUrl
            PublishingState = $publishingState
            Score = $score
            MatchReason = ($reasons -join ', ')
        })
    }

    $orderedCandidates = @(
        $candidates |
            Sort-Object -Property @(
                @{ Expression = 'Score'; Descending = $true },
                @{ Expression = 'Id'; Descending = $false }
            )
    )

    return [pscustomobject]@{
        Selected = if ($orderedCandidates.Count -gt 0) { $orderedCandidates[0].App } else { $null }
        SelectedMatchReason = if ($orderedCandidates.Count -gt 0) { $orderedCandidates[0].MatchReason } else { $null }
        Matches = $orderedCandidates
        MatchCount = $orderedCandidates.Count
    }
}

function Set-AllLicensedUsersAssignment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$AppId,

        [Parameter(Mandatory)]
        [ValidateSet('required', 'available')]
        [string]$Intent,

        [Parameter()]
        [bool]$UninstallOnDeviceRemoval = $true,

        [Parameter()]
        [bool]$PreventICloudAppBackup = $true
    )

    # preventManagedAppBackup is exposed for iosStoreAppAssignmentSettings only
    # through the Microsoft Graph beta schema. App discovery and creation remain
    # on v1.0; only assignment list/create/delete operations use beta.
    $assignmentsUri = "$GraphBetaBaseUri/deviceAppManagement/mobileApps/$AppId/assignments"
    $assignments = @(Get-GraphCollection -Uri $assignmentsUri)

    $matchingAssignments = @(
        $assignments | Where-Object {
            $target = Get-ObjectMemberValue -InputObject $_ -Name 'target'
            if ($null -eq $target) {
                return $false
            }

            $targetType = [string](Get-ObjectMemberValue -InputObject $target -Name '@odata.type')
            $targetType -match '(^|\.)allLicensedUsersAssignmentTarget$'
        }
    )

    $desiredSettings = @{
        '@odata.type' = '#microsoft.graph.iosStoreAppAssignmentSettings'
        uninstallOnDeviceRemoval = $UninstallOnDeviceRemoval
        preventManagedAppBackup = $PreventICloudAppBackup
    }

    # Intune accepts isRemovable only for Required assignments.
    if ($Intent -eq 'required') {
        $desiredSettings.isRemovable = $true
    }

    $assignmentBody = @{
        '@odata.type' = '#microsoft.graph.mobileAppAssignment'
        intent = $Intent
        target = @{
            '@odata.type' = '#microsoft.graph.allLicensedUsersAssignmentTarget'
        }
        settings = $desiredSettings
    }

    $correctAssignment = $null
    foreach ($assignment in $matchingAssignments) {
        $existingIntent = [string](Get-ObjectMemberValue -InputObject $assignment -Name 'intent')
        $existingSettings = Get-ObjectMemberValue -InputObject $assignment -Name 'settings'

        $existingUninstall = Get-ObjectMemberValue -InputObject $existingSettings -Name 'uninstallOnDeviceRemoval'
        $existingPreventBackup = Get-ObjectMemberValue -InputObject $existingSettings -Name 'preventManagedAppBackup'
        $existingIsRemovable = Get-ObjectMemberValue -InputObject $existingSettings -Name 'isRemovable'

        $intentMatches = $existingIntent -eq $Intent
        $uninstallMatches = ([bool]$existingUninstall -eq $UninstallOnDeviceRemoval)
        $backupMatches = ([bool]$existingPreventBackup -eq $PreventICloudAppBackup)
        $removableMatches = if ($Intent -eq 'required') {
            [bool]$existingIsRemovable -eq $true
        }
        else {
            $true
        }

        if ($intentMatches -and $uninstallMatches -and $backupMatches -and $removableMatches) {
            $correctAssignment = $assignment
            break
        }
    }

    if ($null -ne $correctAssignment) {
        $correctAssignmentId = [string](Get-ObjectMemberValue -InputObject $correctAssignment -Name 'id')
        Write-Log -Level SUCCESS -Message "All Licensed Users assignment already has intent '$Intent', Uninstall on device removal='$UninstallOnDeviceRemoval', and Prevent iCloud app backup='$PreventICloudAppBackup' for application $AppId. No assignment change is required."

        # Remove any additional duplicate All Licensed Users assignments while
        # retaining the correctly configured one.
        foreach ($duplicateAssignment in $matchingAssignments) {
            $duplicateId = [string](Get-ObjectMemberValue -InputObject $duplicateAssignment -Name 'id')
            if ([string]::IsNullOrWhiteSpace($duplicateId) -or $duplicateId -eq $correctAssignmentId) {
                continue
            }

            Invoke-IntuneGraphRequest -Method DELETE -Uri "$assignmentsUri/$duplicateId" | Out-Null
            Write-Log -Level WARNING -Message "Removed duplicate All Licensed Users assignment $duplicateId from application $AppId."
        }

        return
    }

    # The Intune backend used by this tenant treats assignment intent, target,
    # and settings as read-only during PATCH. Delete only the matching built-in
    # All Licensed Users assignment(s), then recreate the desired assignment.
    # Unrelated group/user assignments are preserved.
    foreach ($existingAssignment in $matchingAssignments) {
        $assignmentId = [string](Get-ObjectMemberValue -InputObject $existingAssignment -Name 'id')
        if ([string]::IsNullOrWhiteSpace($assignmentId)) {
            throw "An existing All Licensed Users assignment for application $AppId does not contain an assignment ID."
        }

        Invoke-IntuneGraphRequest -Method DELETE -Uri "$assignmentsUri/$assignmentId" | Out-Null
        Write-Log -Level WARNING -Message "Removed existing All Licensed Users assignment $assignmentId from application $AppId so its read-only settings can be corrected."
    }

    Invoke-IntuneGraphRequest -Method POST -Uri $assignmentsUri -Body $assignmentBody | Out-Null
    Write-Log -Level SUCCESS -Message "Created All Licensed Users assignment with intent '$Intent' for application $AppId. Uninstall on device removal='$UninstallOnDeviceRemoval'; Prevent iCloud app backup='$PreventICloudAppBackup'."
}

#endregion Functions

#region Application Catalog

$AppsToDeploy = @(
    @{ Name = 'Microsoft Outlook'; BundleId = 'com.microsoft.office.outlook'; AppStoreId = '951937596'; Intent = 'required' },
    @{ Name = 'Keeper Password Manager'; BundleId = 'com.keepersecurity.KeeperPasswordManager'; AppStoreId = '287170072'; Intent = 'required' },
    @{ Name = 'Adobe Acrobat Reader: Edit PDF'; BundleId = 'com.adobe.Adobe-Reader'; AppStoreId = '469337564'; Intent = 'available' },
    @{ Name = 'Duo Mobile'; BundleId = 'com.duosecurity.duomobile'; AppStoreId = '422663827'; Intent = 'available' },
    @{ Name = 'Firefox Fast & Private Browser'; BundleId = 'org.mozilla.ios.Firefox'; AppStoreId = '989804926'; Intent = 'available' },
    @{ Name = 'Google Chrome'; BundleId = 'com.google.chrome.ios'; AppStoreId = '535886823'; Intent = 'available' },
    @{ Name = 'Intune Company Portal'; BundleId = 'com.microsoft.companyportal'; AppStoreId = '719171358'; Intent = 'available' },
    @{ Name = 'Microsoft Authenticator'; BundleId = 'com.microsoft.azureauthenticator'; AppStoreId = '983156458'; Intent = 'available' },
    @{ Name = 'Microsoft Edge: Web Browser'; BundleId = 'com.microsoft.emmx'; AppStoreId = '1288723196'; Intent = 'available' },
    @{ Name = 'Microsoft Excel'; BundleId = 'com.microsoft.office.excelios'; AppStoreId = '586683407'; Intent = 'available' },
    @{ Name = 'Microsoft OneDrive'; BundleId = 'com.microsoft.skydrive'; AppStoreId = '477537958'; Intent = 'available' },
    @{ Name = 'Microsoft OneNote'; BundleId = 'com.microsoft.office.onenote'; AppStoreId = '410395246'; Intent = 'available' },
    @{ Name = 'Microsoft PowerPoint'; BundleId = 'com.microsoft.office.powerpointios'; AppStoreId = '586449534'; Intent = 'available' },
    @{ Name = 'Microsoft SharePoint'; BundleId = 'com.microsoft.sharepoint'; AppStoreId = '1091505266'; Intent = 'available' },
    @{ Name = 'Microsoft Teams'; BundleId = 'com.microsoft.skype.teams'; AppStoreId = '1113153706'; Intent = 'available' },
    @{ Name = 'Microsoft To Do'; BundleId = 'com.microsoft.to-do-iphone'; AppStoreId = '1212616790'; Intent = 'available' },
    @{ Name = 'Microsoft Word'; BundleId = 'com.microsoft.office.wordios'; AppStoreId = '586447913'; Intent = 'available' },
    @{ Name = 'Zoom Workplace'; BundleId = 'us.zoom.videomeetings'; AppStoreId = '546505307'; Intent = 'available' }
)

#endregion Application Catalog

#region Main

$results = [System.Collections.Generic.List[object]]::new()
$deploymentQueue = [System.Collections.Generic.List[object]]::new()

try {
    Write-Log -Message "Starting Intune iOS app deployment script version $ScriptVersion."
    Write-Log -Message "Log file: $LogPath"
    Write-Log -Message "CSV results file: $CsvPath"

    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
        Write-Log -Message 'Microsoft.Graph.Authentication is not installed. Installing it for the current user.'
        Install-Module -Name Microsoft.Graph.Authentication -Scope CurrentUser -Repository PSGallery -Force -AllowClobber -ErrorAction Stop
    }

    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

    $context = Get-MgContext
    $hasRequiredScope = $false
    $isCorrectEnvironment = $false
    $isCorrectTenant = $true

    if ($null -ne $context) {
        $contextScopes = Get-ObjectMemberValue -InputObject $context -Name 'Scopes'
        if ($null -ne $contextScopes) {
            $hasRequiredScope = $RequiredGraphScope -in @($contextScopes)
        }

        $contextEnvironment = [string](Get-ObjectMemberValue -InputObject $context -Name 'Environment')
        $isCorrectEnvironment = $contextEnvironment -ieq $GraphEnvironment

        if (-not [string]::IsNullOrWhiteSpace($TenantId)) {
            $contextTenantId = [string](Get-ObjectMemberValue -InputObject $context -Name 'TenantId')
            $isCorrectTenant = $contextTenantId -ieq $TenantId
        }
    }

    if ($null -eq $context -or -not $hasRequiredScope -or -not $isCorrectEnvironment -or -not $isCorrectTenant) {
        if ($null -ne $context) {
            Write-Log -Level WARNING -Message "The cached Graph connection is not valid for the requested GCC High tenant or USGov environment. Disconnecting it."
            Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        }

        $connectParameters = @{
            Scopes       = $RequiredGraphScope
            Environment  = $GraphEnvironment
            ContextScope = 'Process'
            NoWelcome    = $true
            ErrorAction  = 'Stop'
        }

        if (-not [string]::IsNullOrWhiteSpace($TenantId)) {
            $connectParameters.TenantId = $TenantId
        }

        Write-Log -Message "Connecting to Microsoft Graph GCC High with environment '$GraphEnvironment' and scope $RequiredGraphScope."
        Connect-MgGraph @connectParameters
        $context = Get-MgContext
    }
    else {
        Write-Log -Message "Using the existing Microsoft Graph GCC High connection for tenant $($context.TenantId)."
    }

    $connectedEnvironment = [string](Get-ObjectMemberValue -InputObject $context -Name 'Environment')
    if ($connectedEnvironment -ine $GraphEnvironment) {
        throw "Microsoft Graph connected to environment '$connectedEnvironment' instead of required GCC High environment '$GraphEnvironment'."
    }

    Write-Log -Message "Microsoft Graph GCC High endpoint: $GraphBaseUri"

    Write-Log -Message 'Phase 1 of 3: validating every catalog entry against the Apple App Store before making any Intune changes.'
    $validatedApps = @(Get-ValidatedAppleCatalog -Catalog $AppsToDeploy -Country $AppleStoreCountry)

    Write-Log -Message 'Retrieving existing Intune mobile applications.'
    $allMobileApps = @(Get-GraphCollection -Uri "$GraphBaseUri/deviceAppManagement/mobileApps")

    Write-Log -Message 'Phase 2 of 3: creating missing application objects and updating supported mutable metadata on existing apps.'

    foreach ($appInfo in $validatedApps) {
        $appName = [string]$appInfo.Name
        $bundleId = [string]$appInfo.BundleId
        $appStoreId = [string]$appInfo.AppStoreId
        $appStoreUrl = [string]$appInfo.AppStoreUrl
        $intent = [string]$appInfo.Intent
        $appId = $null
        $action = $null

        Write-Host ''
        Write-Log -Message "Preparing $appName [$bundleId]."

        try {
            $existingMatch = Get-ExistingIosStoreApp -MobileApps $allMobileApps -BundleId $bundleId -AppStoreId $appStoreId -DisplayName $appName
            $existingApp = $existingMatch.Selected

            if ($null -ne $existingApp) {
                $appId = [string](Get-ObjectMemberValue -InputObject $existingApp -Name 'id')
                if ([string]::IsNullOrWhiteSpace($appId)) {
                    throw "The existing application '$appName' does not contain an Intune application ID."
                }

                $action = 'Existing app assigned'
                Write-Log -Message "Application already exists with ID $appId. Match: $($existingMatch.SelectedMatchReason). Creation will be skipped."

                if ($existingMatch.MatchCount -gt 1) {
                    $duplicateSummary = @($existingMatch.Matches | ForEach-Object {
                        "ID=$($_.Id); Name='$($_.DisplayName)'; BundleId='$($_.BundleId)'; Match='$($_.MatchReason)'"
                    }) -join ' | '

                    Write-Log -Level WARNING -Message "Found $($existingMatch.MatchCount) existing Intune iOS app objects matching '$appName'. The script will reuse ID $appId and will not create another object. Existing matches: $duplicateSummary"
                }

                $existingDisplayName = [string](Get-ObjectMemberValue -InputObject $existingApp -Name 'displayName')
                if (-not [string]::IsNullOrWhiteSpace($existingDisplayName) -and $existingDisplayName -ne $appName) {
                    Write-Log -Level WARNING -Message "Existing application display name is '$existingDisplayName'; catalog display name is '$appName'. The configured display name will be retained unless metadata update is required."
                }

                $fullExistingApp = Invoke-IntuneGraphRequest -Method GET -Uri "$GraphBaseUri/deviceAppManagement/mobileApps/$appId"
                if ($UpdateExistingAppMetadata -and (Test-IosStoreAppMetadataDrift -ExistingApp $fullExistingApp -DesiredMetadata $appInfo)) {
                    $updatePayload = New-IosStoreAppUpdatePayload -AppMetadata $appInfo
                    Invoke-IntuneGraphRequest -Method PATCH -Uri "$GraphBaseUri/deviceAppManagement/mobileApps/$appId" -Body $updatePayload | Out-Null
                    $action = 'Existing app metadata updated and assigned'
                    Write-Log -Level SUCCESS -Message "Updated supported mutable metadata for $appName. App Store URL and bundle ID were retained because Intune does not accept them in PATCH requests."
                    $fullExistingApp = Invoke-IntuneGraphRequest -Method GET -Uri "$GraphBaseUri/deviceAppManagement/mobileApps/$appId"
                }
                elseif ($UpdateExistingAppMetadata) {
                    Write-Log -Message "Existing Apple App Store metadata for $appName is current."
                }
                else {
                    Write-Log -Message "Existing metadata updates are disabled. The current Intune app object will be retained."
                }

                $initialState = [string](Get-ObjectMemberValue -InputObject $fullExistingApp -Name 'publishingState')
            }
            else {
                $appBody = New-IosStoreAppPayload -AppMetadata $appInfo

                $createdApp = Invoke-IntuneGraphRequest -Method POST -Uri "$GraphBaseUri/deviceAppManagement/mobileApps" -Body $appBody
                $appId = [string](Get-ObjectMemberValue -InputObject $createdApp -Name 'id')

                if ([string]::IsNullOrWhiteSpace($appId)) {
                    throw "Microsoft Graph did not return an application ID after creating '$appName'."
                }

                $action = 'Created and assigned'
                $initialState = [string](Get-ObjectMemberValue -InputObject $createdApp -Name 'publishingState')
                Write-Log -Level SUCCESS -Message "Created application with ID $appId."

                $allMobileApps += $createdApp
            }

            $deploymentQueue.Add([pscustomobject]@{
                Application = $appName
                BundleId = $bundleId
                AppStoreUrl = $appStoreUrl
                Intent = $intent
                AppId = $appId
                Action = $action
                InitialState = $initialState
                Completed = $false
            })
        }
        catch {
            $errorMessage = Get-GraphErrorMessage -ErrorRecord $_
            Write-Log -Level ERROR -Message "Failed to prepare $appName. $errorMessage"

            $results.Add([pscustomobject]@{
                Application = $appName
                BundleId = $bundleId
                AppStoreUrl = $appStoreUrl
                Intent = $intent
                AppId = $appId
                Action = 'Create or discover app'
                Status = 'Failed'
                Error = $errorMessage
            })
        }
    }

    Write-Host ''
    Write-Log -Message "Phase 2 complete. $($deploymentQueue.Count) application(s) are ready for publication checks and assignment."
    Write-Log -Message 'Phase 3 of 3: waiting for applications to publish, then applying assignments.'

    $publishDeadline = (Get-Date).AddSeconds($PublishTimeoutSeconds)
    $pollCycle = 0

    while (@($deploymentQueue | Where-Object { -not $_.Completed }).Count -gt 0 -and (Get-Date) -lt $publishDeadline) {
        $pollCycle++
        $pendingItems = @($deploymentQueue | Where-Object { -not $_.Completed })
        Write-Log -Message "Publication check cycle $pollCycle. Pending applications: $($pendingItems.Count)."

        foreach ($queueItem in $pendingItems) {
            try {
                $appUri = "$GraphBaseUri/deviceAppManagement/mobileApps/$($queueItem.AppId)"
                $currentApp = Invoke-IntuneGraphRequest -Method GET -Uri $appUri
                $publishingState = [string](Get-ObjectMemberValue -InputObject $currentApp -Name 'publishingState')

                switch ($publishingState) {
                    'published' {
                        Write-Log -Level SUCCESS -Message "$($queueItem.Application) is published. Applying '$($queueItem.Intent)' assignment."
                        Set-AllLicensedUsersAssignment -AppId $queueItem.AppId -Intent $queueItem.Intent -UninstallOnDeviceRemoval $true

                        $results.Add([pscustomobject]@{
                            Application = $queueItem.Application
                            BundleId = $queueItem.BundleId
                            AppStoreUrl = $queueItem.AppStoreUrl
                            Intent = $queueItem.Intent
                            AppId = $queueItem.AppId
                            Action = $queueItem.Action
                            Status = 'Success'
                            Error = $null
                        })

                        $queueItem.Completed = $true
                    }

                    'notPublished' {
                        $message = "The Intune application entered the notPublished state."
                        Write-Log -Level ERROR -Message "$($queueItem.Application): $message"

                        $results.Add([pscustomobject]@{
                            Application = $queueItem.Application
                            BundleId = $queueItem.BundleId
                            AppStoreUrl = $queueItem.AppStoreUrl
                            Intent = $queueItem.Intent
                            AppId = $queueItem.AppId
                            Action = $queueItem.Action
                            Status = 'Failed'
                            Error = $message
                        })

                        $queueItem.Completed = $true
                    }

                    default {
                        $displayState = if ([string]::IsNullOrWhiteSpace($publishingState)) { 'unknown' } else { $publishingState }
                        Write-Log -Message "$($queueItem.Application) publishing state is '$displayState'."
                    }
                }
            }
            catch {
                $errorMessage = Get-GraphErrorMessage -ErrorRecord $_
                Write-Log -Level ERROR -Message "Failed while checking or assigning $($queueItem.Application). $errorMessage"

                $results.Add([pscustomobject]@{
                    Application = $queueItem.Application
                    BundleId = $queueItem.BundleId
                    AppStoreUrl = $queueItem.AppStoreUrl
                    Intent = $queueItem.Intent
                    AppId = $queueItem.AppId
                    Action = $queueItem.Action
                    Status = 'Failed'
                    Error = $errorMessage
                })

                $queueItem.Completed = $true
            }
        }

        if (@($deploymentQueue | Where-Object { -not $_.Completed }).Count -gt 0 -and (Get-Date) -lt $publishDeadline) {
            Write-Log -Message "Waiting $PublishPollIntervalSeconds second(s) before the next publication check cycle."
            Start-Sleep -Seconds $PublishPollIntervalSeconds
        }
    }

    $timedOutItems = @($deploymentQueue | Where-Object { -not $_.Completed })
    foreach ($queueItem in $timedOutItems) {
        $message = "Application did not reach the published state within $PublishTimeoutSeconds seconds. The app object remains in Intune and can be processed by rerunning the script later."
        Write-Log -Level ERROR -Message "$($queueItem.Application): $message"

        $results.Add([pscustomobject]@{
            Application = $queueItem.Application
            BundleId = $queueItem.BundleId
            AppStoreUrl = $queueItem.AppStoreUrl
            Intent = $queueItem.Intent
            AppId = $queueItem.AppId
            Action = $queueItem.Action
            Status = 'Failed'
            Error = $message
        })

        $queueItem.Completed = $true
    }
}
catch {
    $fatalError = Get-GraphErrorMessage -ErrorRecord $_
    Write-Log -Level ERROR -Message "Fatal script failure. $fatalError"

    $results.Add([pscustomobject]@{
        Application = 'Script execution'
        BundleId = $null
        AppStoreUrl = $null
        Intent = $null
        AppId = $null
        Action = 'Fatal error'
        Status = 'Failed'
        Error = $fatalError
    })
}
finally {
    try {
        $results | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8
    }
    catch {
        Write-Log -Level ERROR -Message "Unable to export CSV results. $($_.Exception.Message)"
    }

    Write-Host ''
    Write-Host 'Intune iOS Application Deployment Results' -ForegroundColor Cyan
    $results | Format-Table Application, Intent, Action, Status, AppId -AutoSize

    $failureCount = @($results | Where-Object { $_.Status -eq 'Failed' }).Count
    $successCount = @($results | Where-Object { $_.Status -eq 'Success' }).Count

    Write-Log -Message "Successful applications: $successCount"

    if ($failureCount -gt 0) {
        Write-Log -Level ERROR -Message "Failed applications: $failureCount"
        Write-Log -Level ERROR -Message "Review the log file at $LogPath and CSV file at $CsvPath."
    }
    else {
        Write-Log -Level SUCCESS -Message 'All iOS application configurations completed successfully.'
    }
}

if (@($results | Where-Object { $_.Status -eq 'Failed' }).Count -gt 0) {
    exit 1
}

exit 0

#endregion Main
