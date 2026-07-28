<#
.SYNOPSIS
    Creates and assigns the Windows Company Portal Microsoft Store app in Intune.
.DESCRIPTION
    Creates Company Portal as a Microsoft Store app (new) / WinGet app with System install behavior,
    waits for publication, and assigns it as Required to All Devices. Existing matching app objects
    and assignments are reused to prevent duplicates.
.NOTES
    Version: 1.0.0
    Cloud: Microsoft Graph US Government L4 (GCC High)
    Store ID / Package Identifier: 9WZDNCRFJ3PZ
#>

[CmdletBinding()]
param(
    [string]$TenantId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptVersion = '1.0.0'
$GraphEnvironment = 'USGov'
$GraphRoot = 'https://graph.microsoft.us/beta'
$RequiredScopes = @('DeviceManagementApps.ReadWrite.All')

$AppDisplayName = 'Company Portal'
$AppPublisher = 'Microsoft Corporation'
$PackageIdentifier = '9WZDNCRFJ3PZ'
$AssignmentIntent = 'required'
$PublishingTimeoutSeconds = 600
$PollIntervalSeconds = 10

$LogRoot = 'C:\Temp'
$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogPath = Join-Path $LogRoot "Intune-Company-Portal-GCCH-$Timestamp.log"

if (-not (Test-Path -LiteralPath $LogRoot)) {
    New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null
}

function Write-Log {
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

    $line = "{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    Write-Host "[$Level] $Message" -ForegroundColor $color
}

function Get-GraphValue {
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory)][string]$Name
    )

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
    $nextLink = $Uri

    while (-not [string]::IsNullOrWhiteSpace($nextLink)) {
        $response = Invoke-MgGraphRequest -Method GET -Uri $nextLink -ErrorAction Stop
        $value = Get-GraphValue -InputObject $response -Name 'value'

        if ($null -ne $value) {
            foreach ($item in @($value)) {
                if ($null -ne $item) { $items.Add($item) }
            }
        }
        elseif ($response -is [System.Array]) {
            foreach ($item in $response) {
                if ($null -ne $item) { $items.Add($item) }
            }
        }

        $nextValue = Get-GraphValue -InputObject $response -Name '@odata.nextLink'
        $nextLink = if ([string]::IsNullOrWhiteSpace([string]$nextValue)) { $null } else { [string]$nextValue }
    }

    return $items.ToArray()
}

function Connect-RequiredGraphEnvironment {
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
        Write-Log -Message 'Installing Microsoft.Graph.Authentication.'
        Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
    }

    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

    $context = Get-MgContext
    $needsConnection = $true

    if ($null -ne $context) {
        $sameEnvironment = [string]$context.Environment -eq $GraphEnvironment
        $scopeMatch = @($RequiredScopes | Where-Object { $_ -notin @($context.Scopes) }).Count -eq 0
        $tenantMatch = [string]::IsNullOrWhiteSpace($TenantId) -or [string]$context.TenantId -eq $TenantId

        if ($sameEnvironment -and $scopeMatch -and $tenantMatch) {
            $needsConnection = $false
            Write-Log -Message "Using existing Microsoft Graph connection for tenant $($context.TenantId)."
        }
    }

    if ($needsConnection) {
        if ($null -ne $context) {
            Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        }

        $connectParams = @{
            Scopes      = $RequiredScopes
            Environment = $GraphEnvironment
            NoWelcome   = $true
            ErrorAction = 'Stop'
        }

        if (-not [string]::IsNullOrWhiteSpace($TenantId)) {
            $connectParams.TenantId = $TenantId
        }

        Write-Log -Message "Connecting to Microsoft Graph environment '$GraphEnvironment'."
        Connect-MgGraph @connectParams | Out-Null
    }
}

function Find-ExistingCompanyPortalApp {
    $apps = Get-GraphCollection -Uri "$GraphRoot/deviceAppManagement/mobileApps"

    $matches = @(
        $apps | Where-Object {
            $odataType = [string](Get-GraphValue -InputObject $_ -Name '@odata.type')
            $packageId = [string](Get-GraphValue -InputObject $_ -Name 'packageIdentifier')
            $displayName = [string](Get-GraphValue -InputObject $_ -Name 'displayName')

            ($odataType -eq '#microsoft.graph.winGetApp') -and
            (
                $packageId -ieq $PackageIdentifier -or
                $displayName -ieq $AppDisplayName
            )
        }
    )

    if ($matches.Count -gt 1) {
        $ids = @($matches | ForEach-Object { [string](Get-GraphValue -InputObject $_ -Name 'id') }) -join ', '
        Write-Log -Level WARNING -Message "Found $($matches.Count) matching Company Portal app objects. Reusing the first match. IDs: $ids"
    }

    return $matches | Select-Object -First 1
}

function Wait-AppPublished {
    param([Parameter(Mandatory)][string]$AppId)

    $deadline = (Get-Date).AddSeconds($PublishingTimeoutSeconds)

    do {
        $app = Invoke-MgGraphRequest -Method GET -Uri "$GraphRoot/deviceAppManagement/mobileApps/$AppId" -ErrorAction Stop
        $state = [string](Get-GraphValue -InputObject $app -Name 'publishingState')

        if ($state -eq 'published') {
            Write-Log -Level SUCCESS -Message "Company Portal app is published. App ID: $AppId"
            return
        }

        if ($state -eq 'notPublished') {
            throw "Company Portal entered publishing state 'notPublished'."
        }

        Write-Log -Message "Company Portal publishing state is '$state'. Waiting $PollIntervalSeconds second(s)."
        Start-Sleep -Seconds $PollIntervalSeconds
    }
    while ((Get-Date) -lt $deadline)

    throw "Company Portal did not reach publishing state 'published' within $PublishingTimeoutSeconds seconds."
}

function Ensure-AllDevicesRequiredAssignment {
    param([Parameter(Mandatory)][string]$AppId)

    $assignmentsUri = "$GraphRoot/deviceAppManagement/mobileApps/$AppId/assignments"
    $assignments = Get-GraphCollection -Uri $assignmentsUri

    $existing = $assignments | Where-Object {
        $target = Get-GraphValue -InputObject $_ -Name 'target'
        $targetType = [string](Get-GraphValue -InputObject $target -Name '@odata.type')
        $intent = [string](Get-GraphValue -InputObject $_ -Name 'intent')

        $targetType -eq '#microsoft.graph.allDevicesAssignmentTarget' -and
        $intent -eq $AssignmentIntent
    } | Select-Object -First 1

    if ($null -ne $existing) {
        Write-Log -Level SUCCESS -Message 'Required assignment to All Devices already exists. No assignment changes are needed.'
        return
    }

    $assignmentBody = @{
        '@odata.type' = '#microsoft.graph.mobileAppAssignment'
        intent = $AssignmentIntent
        target = @{
            '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget'
        }
        settings = @{
            '@odata.type' = '#microsoft.graph.winGetAppAssignmentSettings'
            notifications = 'showAll'
        }
    }

    Invoke-MgGraphRequest -Method POST -Uri $assignmentsUri -Body $assignmentBody -ContentType 'application/json' -ErrorAction Stop | Out-Null
    Write-Log -Level SUCCESS -Message 'Created Required assignment to All Devices.'
}

try {
    Write-Log -Message "Starting GCC High Company Portal deployment script version $ScriptVersion."
    Write-Log -Message "Log file: $LogPath"

    Connect-RequiredGraphEnvironment

    Write-Log -Message 'Checking Intune for an existing Company Portal Microsoft Store app.'
    $existingApp = Find-ExistingCompanyPortalApp

    if ($null -ne $existingApp) {
        $appId = [string](Get-GraphValue -InputObject $existingApp -Name 'id')
        $existingPackageId = [string](Get-GraphValue -InputObject $existingApp -Name 'packageIdentifier')
        Write-Log -Level SUCCESS -Message "Existing Company Portal app found. App ID: $appId; Package identifier: $existingPackageId. Creation skipped."
    }
    else {
        $appBody = @{
            '@odata.type' = '#microsoft.graph.winGetApp'
            displayName = $AppDisplayName
            description = 'Microsoft Intune Company Portal deployed by Resilient IT automation.'
            publisher = $AppPublisher
            isFeatured = $false
            owner = 'Resilient IT'
            developer = 'Microsoft Corporation'
            notes = "Created by Resilient IT automation. Store ID: $PackageIdentifier"
            packageIdentifier = $PackageIdentifier
            installExperience = @{
                '@odata.type' = 'microsoft.graph.winGetAppInstallExperience'
                runAsAccount = 'system'
            }
        }

        Write-Log -Message "Creating Company Portal as Microsoft Store app (new) using Store ID $PackageIdentifier."
        $createdApp = Invoke-MgGraphRequest -Method POST -Uri "$GraphRoot/deviceAppManagement/mobileApps" -Body $appBody -ContentType 'application/json' -ErrorAction Stop
        $appId = [string](Get-GraphValue -InputObject $createdApp -Name 'id')

        if ([string]::IsNullOrWhiteSpace($appId)) {
            throw 'Microsoft Graph did not return an app ID after creating Company Portal.'
        }

        Write-Log -Level SUCCESS -Message "Created Company Portal app. App ID: $appId"
    }

    Wait-AppPublished -AppId $appId
    Ensure-AllDevicesRequiredAssignment -AppId $appId

    Write-Log -Level SUCCESS -Message 'Company Portal deployment configuration completed successfully.'
    Write-Host ''
    Write-Host "App ID: $appId" -ForegroundColor Green
    Write-Host 'Install behavior: System' -ForegroundColor Green
    Write-Host 'Assignment: Required - All Devices' -ForegroundColor Green
    exit 0
}
catch {
    Write-Log -Level ERROR -Message $_.Exception.Message
    Write-Log -Level ERROR -Message "Company Portal deployment failed. Review $LogPath"
    exit 1
}
