<#
.SYNOPSIS
    Creates or updates an Intune Windows platform script that removes selected inbox applications.
.DESCRIPTION
    Uploads the embedded removal script to Microsoft Intune and assigns it to All Devices.
    Existing Intune script objects with the same display name are updated rather than duplicated.
.NOTES
    Version: 1.0.0
    Cloud: Global
#>

[CmdletBinding()]
param(
    [string]$TenantId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptVersion = '1.0.0'
$GraphEnvironment = 'Global'
$GraphRoot = 'https://graph.microsoft.com/beta'
$DisplayName = 'RIT - Remove Windows Inbox Apps'
$FileName = 'Remove-Windows-Inbox-Apps.ps1'
$RequiredScopes = @(
    'DeviceManagementScripts.ReadWrite.All',
    'DeviceManagementConfiguration.ReadWrite.All'
)

function Write-Status {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','SUCCESS','WARNING','ERROR')][string]$Level = 'INFO'
    )
    $color = switch ($Level) {
        'SUCCESS' { 'Green' }
        'WARNING' { 'Yellow' }
        'ERROR'   { 'Red' }
        default   { 'Cyan' }
    }
    Write-Host "[$Level] $Message" -ForegroundColor $color
}

function Get-GraphValue {
    param([AllowNull()][object]$InputObject,[Parameter(Mandatory)][string]$Name)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) { return $InputObject[$Name] }
        return $null
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $null
}

function Get-GraphCollection {
    param([Parameter(Mandatory)][string]$Uri)
    $items = [System.Collections.Generic.List[object]]::new()
    $next = $Uri
    while (-not [string]::IsNullOrWhiteSpace($next)) {
        $response = Invoke-MgGraphRequest -Method GET -Uri $next -ErrorAction Stop
        $value = Get-GraphValue -InputObject $response -Name 'value'
        if ($null -ne $value) {
            foreach ($item in @($value)) { if ($null -ne $item) { $items.Add($item) } }
        } elseif ($response -is [System.Array]) {
            foreach ($item in $response) { if ($null -ne $item) { $items.Add($item) } }
        }
        $nextValue = Get-GraphValue -InputObject $response -Name '@odata.nextLink'
        $next = if ([string]::IsNullOrWhiteSpace([string]$nextValue)) { $null } else { [string]$nextValue }
    }
    return $items.ToArray()
}

Write-Status -Message "Starting Windows inbox app removal deployment version $ScriptVersion."

if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
    Write-Status -Message 'Installing Microsoft.Graph.Authentication.'
    Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
}
Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

$context = Get-MgContext
$needsConnection = $true
if ($null -ne $context) {
    $sameEnvironment = [string]$context.Environment -eq $GraphEnvironment
    $scopeMatch = @($RequiredScopes | Where-Object { $_ -notin @($context.Scopes) }).Count -eq 0
    $tenantMatch = [string]::IsNullOrWhiteSpace($TenantId) -or [string]$context.TenantId -eq $TenantId
    if ($sameEnvironment -and $scopeMatch -and $tenantMatch) { $needsConnection = $false }
}

if ($needsConnection) {
    if ($null -ne $context) { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null }
    $connectParams = @{ Scopes = $RequiredScopes; Environment = $GraphEnvironment; NoWelcome = $true; ErrorAction = 'Stop' }
    if (-not [string]::IsNullOrWhiteSpace($TenantId)) { $connectParams.TenantId = $TenantId }
    Write-Status -Message "Connecting to Microsoft Graph environment '$GraphEnvironment'."
    Connect-MgGraph @connectParams | Out-Null
}

$RemovalScript = @'
<#
.SYNOPSIS
    Removes selected Windows inbox and Microsoft Store applications.
.DESCRIPTION
    Intended for Microsoft Intune deployment in the SYSTEM context using 64-bit PowerShell.
    Removes matching installed Appx packages for all users and matching provisioned packages
    so the applications are not installed for newly created profiles.

    This script intentionally targets only the Microsoft Store/Appx "Microsoft 365 (Office)"
    hub package (Microsoft.MicrosoftOfficeHub). It does not remove Microsoft 365 Apps,
    Office Click-to-Run, MSI Office, or Microsoft 365 desktop applications.
.NOTES
    Version: 1.0.0
    Logs: C:\Temp\Windows-Inbox-App-Removal-<timestamp>.log
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptVersion = '1.0.0'
$LogRoot = 'C:\Temp'
$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogPath = Join-Path $LogRoot "Windows-Inbox-App-Removal-$Timestamp.log"

if (-not (Test-Path -LiteralPath $LogRoot)) {
    New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO','SUCCESS','WARNING','ERROR')]
        [string]$Level = 'INFO'
    )

    $line = "{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    Write-Output $line
}

# Match values are Appx package Name patterns, not display names.
$Targets = @(
    [pscustomobject]@{ DisplayName = '3D Viewer';                     Patterns = @('Microsoft.Microsoft3DViewer') },
    [pscustomobject]@{ DisplayName = 'Cortana';                       Patterns = @('Microsoft.549981C3F5F10') },
    [pscustomobject]@{ DisplayName = 'Dell Optimizer App for Dell PCs'; Patterns = @('DellInc.DellOptimizer*','DellInc.DellOptimizerforDellPCs*') },
    [pscustomobject]@{ DisplayName = 'Feedback Hub';                  Patterns = @('Microsoft.WindowsFeedbackHub') },
    [pscustomobject]@{ DisplayName = 'Mail and Calendar';             Patterns = @('microsoft.windowscommunicationsapps') },
    [pscustomobject]@{ DisplayName = 'Microsoft 365 (Office)';        Patterns = @('Microsoft.MicrosoftOfficeHub') },
    [pscustomobject]@{ DisplayName = 'Microsoft Family Safety';       Patterns = @('MicrosoftCorporationII.MicrosoftFamily','MicrosoftCorporationII.MicrosoftFamilySafety') },
    [pscustomobject]@{ DisplayName = 'Microsoft Journal';             Patterns = @('Microsoft.MicrosoftJournal') },
    [pscustomobject]@{ DisplayName = 'Microsoft Messaging';           Patterns = @('Microsoft.Messaging') },
    [pscustomobject]@{ DisplayName = 'Microsoft News';                Patterns = @('Microsoft.BingNews') },
    [pscustomobject]@{ DisplayName = 'Microsoft Remote Desktop';      Patterns = @('Microsoft.RemoteDesktop','MicrosoftCorporationII.Windows365') },
    [pscustomobject]@{ DisplayName = 'Mixed Reality Portal';          Patterns = @('Microsoft.MixedReality.Portal') },
    [pscustomobject]@{ DisplayName = 'Mobile Plans';                   Patterns = @('Microsoft.OneConnect') },
    [pscustomobject]@{ DisplayName = 'Movies & TV';                    Patterns = @('Microsoft.ZuneVideo') },
    [pscustomobject]@{ DisplayName = 'MSN Weather';                    Patterns = @('Microsoft.BingWeather') },
    [pscustomobject]@{ DisplayName = 'Outlook for Windows';           Patterns = @('Microsoft.OutlookForWindows') },
    [pscustomobject]@{ DisplayName = 'Quick Assist';                   Patterns = @('MicrosoftCorporationII.QuickAssist') },
    [pscustomobject]@{ DisplayName = 'Skype';                          Patterns = @('Microsoft.SkypeApp') },
    [pscustomobject]@{ DisplayName = 'Windows Maps';                   Patterns = @('Microsoft.WindowsMaps') },
    [pscustomobject]@{ DisplayName = 'Xbox';                           Patterns = @('Microsoft.GamingApp','Microsoft.XboxApp') },
    [pscustomobject]@{ DisplayName = 'Xbox Accessories';               Patterns = @('Microsoft.XboxDevices') }
)

function Test-PatternMatch {
    param(
        [Parameter(Mandatory)]
        [string]$Value,

        [Parameter(Mandatory)]
        [string[]]$Patterns
    )

    foreach ($pattern in $Patterns) {
        if ($Value -like $pattern) {
            return $true
        }
    }

    return $false
}

function Remove-InstalledAppxPackage {
    param(
        [Parameter(Mandatory)]
        [object]$Package,

        [Parameter(Mandatory)]
        [string]$FriendlyName
    )

    try {
        $removeCommand = Get-Command -Name Remove-AppxPackage -ErrorAction Stop

        if ($removeCommand.Parameters.ContainsKey('AllUsers')) {
            Remove-AppxPackage -Package $Package.PackageFullName -AllUsers -ErrorAction Stop
        }
        else {
            Remove-AppxPackage -Package $Package.PackageFullName -ErrorAction Stop
        }

        Write-Log -Level SUCCESS -Message "Removed installed package '$($Package.PackageFullName)' for $FriendlyName."
        return $true
    }
    catch {
        Write-Log -Level WARNING -Message "Could not remove installed package '$($Package.PackageFullName)' for $FriendlyName. $($_.Exception.Message)"
        return $false
    }
}

function Remove-ProvisionedAppxPackage {
    param(
        [Parameter(Mandatory)]
        [object]$Package,

        [Parameter(Mandatory)]
        [string]$FriendlyName
    )

    try {
        Remove-AppxProvisionedPackage -Online -PackageName $Package.PackageName -AllUsers -ErrorAction Stop | Out-Null
        Write-Log -Level SUCCESS -Message "Removed provisioned package '$($Package.PackageName)' for $FriendlyName."
        return $true
    }
    catch {
        Write-Log -Level WARNING -Message "Could not remove provisioned package '$($Package.PackageName)' for $FriendlyName. $($_.Exception.Message)"
        return $false
    }
}

Write-Log -Message "Starting Windows inbox app removal version $ScriptVersion."
Write-Log -Message "Running as '$([Security.Principal.WindowsIdentity]::GetCurrent().Name)' on '$env:COMPUTERNAME'."

$removedCount = 0
$failedCount = 0
$matchedCount = 0

try {
    $installedPackages = @(Get-AppxPackage -AllUsers -ErrorAction Stop)
    $provisionedPackages = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop)

    foreach ($target in $Targets) {
        Write-Log -Message "Evaluating $($target.DisplayName)."

        $installedMatches = @(
            $installedPackages | Where-Object {
                Test-PatternMatch -Value ([string]$_.Name) -Patterns $target.Patterns
            }
        )

        $provisionedMatches = @(
            $provisionedPackages | Where-Object {
                Test-PatternMatch -Value ([string]$_.DisplayName) -Patterns $target.Patterns
            }
        )

        $matchedCount += $installedMatches.Count + $provisionedMatches.Count

        foreach ($package in $installedMatches) {
            if (Remove-InstalledAppxPackage -Package $package -FriendlyName $target.DisplayName) {
                $removedCount++
            }
            else {
                $failedCount++
            }
        }

        foreach ($package in $provisionedMatches) {
            if (Remove-ProvisionedAppxPackage -Package $package -FriendlyName $target.DisplayName) {
                $removedCount++
            }
            else {
                $failedCount++
            }
        }

        if ($installedMatches.Count -eq 0 -and $provisionedMatches.Count -eq 0) {
            Write-Log -Message "$($target.DisplayName) was not detected."
        }
    }

    # Refresh inventory and verify targeted packages are no longer present.
    $remainingInstalled = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)
    $remainingProvisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)
    $remaining = [System.Collections.Generic.List[string]]::new()

    foreach ($target in $Targets) {
        $hasInstalled = @($remainingInstalled | Where-Object {
            Test-PatternMatch -Value ([string]$_.Name) -Patterns $target.Patterns
        }).Count -gt 0

        $hasProvisioned = @($remainingProvisioned | Where-Object {
            Test-PatternMatch -Value ([string]$_.DisplayName) -Patterns $target.Patterns
        }).Count -gt 0

        if ($hasInstalled -or $hasProvisioned) {
            $remaining.Add($target.DisplayName)
        }
    }

    Write-Log -Message "Matched package instances: $matchedCount. Removed package instances: $removedCount. Removal failures: $failedCount."

    if ($remaining.Count -gt 0) {
        Write-Log -Level WARNING -Message "The following targets remain detected: $($remaining -join ', '). Some protected or in-use packages may require a restart or a later retry."
    }
    else {
        Write-Log -Level SUCCESS -Message 'All targeted Appx applications are absent from the current installed and provisioned package inventory.'
    }

    # Return success so Intune does not repeatedly report a failed platform script when Windows protects an app.
    exit 0
}
catch {
    Write-Log -Level ERROR -Message "Fatal removal error: $($_.Exception.Message)"
    exit 1
}

'@

$scriptBytes = [System.Text.Encoding]::UTF8.GetBytes($RemovalScript)
$scriptContent = [Convert]::ToBase64String($scriptBytes)

Write-Status -Message 'Retrieving existing Intune platform scripts.'
$existingScripts = @(Get-GraphCollection -Uri "$GraphRoot/deviceManagement/deviceManagementScripts")
$matches = @($existingScripts | Where-Object { [string](Get-GraphValue $_ 'displayName') -eq $DisplayName })

if ($matches.Count -gt 1) {
    Write-Status -Level WARNING -Message "Found $($matches.Count) platform scripts named '$DisplayName'. The newest object will be updated; no additional duplicate will be created."
    $existing = $matches | Sort-Object { [datetime](Get-GraphValue $_ 'lastModifiedDateTime') } -Descending | Select-Object -First 1
} else {
    $existing = $matches | Select-Object -First 1
}

$body = @{
    '@odata.type' = '#microsoft.graph.deviceManagementScript'
    displayName = $DisplayName
    description = 'Removes selected Windows inbox and Microsoft Store Appx packages for all users and from provisioning. Does not remove Microsoft 365 desktop applications.'
    scriptContent = $scriptContent
    runAsAccount = 'system'
    enforceSignatureCheck = $false
    fileName = $FileName
    roleScopeTagIds = @('0')
    runAs32Bit = $false
}

if ($null -eq $existing) {
    Write-Status -Message "Creating Intune platform script '$DisplayName'."
    $created = Invoke-MgGraphRequest -Method POST -Uri "$GraphRoot/deviceManagement/deviceManagementScripts" -Body $body -ContentType 'application/json' -ErrorAction Stop
    $scriptId = [string](Get-GraphValue $created 'id')
    Write-Status -Level SUCCESS -Message "Created platform script with ID $scriptId."
} else {
    $scriptId = [string](Get-GraphValue $existing 'id')
    Write-Status -Message "Updating existing platform script ID $scriptId."
    Invoke-MgGraphRequest -Method PATCH -Uri "$GraphRoot/deviceManagement/deviceManagementScripts/$scriptId" -Body $body -ContentType 'application/json' -ErrorAction Stop | Out-Null
    Write-Status -Level SUCCESS -Message 'Updated the existing platform script content and settings.'
}

Write-Status -Message 'Checking platform script assignments.'
$assignments = @(Get-GraphCollection -Uri "$GraphRoot/deviceManagement/deviceManagementScripts/$scriptId/assignments")
$allDevicesAssignment = $assignments | Where-Object {
    $target = Get-GraphValue $_ 'target'
    [string](Get-GraphValue $target '@odata.type') -eq '#microsoft.graph.allDevicesAssignmentTarget'
} | Select-Object -First 1

if ($null -eq $allDevicesAssignment) {
    $assignmentBody = @{
        '@odata.type' = '#microsoft.graph.deviceManagementScriptAssignment'
        target = @{
            '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget'
            deviceAndAppManagementAssignmentFilterType = 'none'
        }
    }
    Invoke-MgGraphRequest -Method POST -Uri "$GraphRoot/deviceManagement/deviceManagementScripts/$scriptId/assignments" -Body $assignmentBody -ContentType 'application/json' -ErrorAction Stop | Out-Null
    Write-Status -Level SUCCESS -Message 'Assigned the platform script to All Devices.'
} else {
    Write-Status -Message 'The platform script is already assigned to All Devices. Assignment creation was skipped.'
}

Write-Status -Level SUCCESS -Message 'Windows inbox app removal deployment completed.'
Write-Host "Intune script ID: $scriptId"
