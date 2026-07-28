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
