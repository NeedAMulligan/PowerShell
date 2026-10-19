#Requires -Version 5.1
<#
.SYNOPSIS
    Disables Windows Insider Preview participation and hides its Settings page.
.DESCRIPTION
    Configures device-level Windows Insider and Windows Update policies, while
    preserving any existing SettingsPageVisibility restrictions. Logs and
    validates changes. Intended for elevated local execution or SYSTEM.
.VERSION
    1.1.0
.NOTES
    Resilient IT | Windows endpoint build process
    No restart is initiated. Existing MDM/GPO policy may override local settings.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$LogDirectory = 'C:\Temp'
$LogFile = Join-Path $LogDirectory ('RIT-DisableWindowsInsider_{0}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
$Failures = 0

function Write-Log {
    param([Parameter(Mandatory)][string]$Message, [ValidateSet('INFO','SUCCESS','WARN','ERROR')][string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
    if (Test-Path -LiteralPath $LogDirectory) { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 }
}

function Set-VerifiedRegistryValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][object]$Value,
        [Parameter(Mandatory)][ValidateSet('DWord','String')][string]$Type
    )
    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
        }
        New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
        $property = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
        $actual = $property.$Name
        $kind = (Get-Item -LiteralPath $Path -ErrorAction Stop).GetValueKind($Name)
        if ([string]$actual -cne [string]$Value -or [string]$kind -ne $Type) {
            throw "Verification failed: expected '$Value' ($Type), found '$actual' ($kind)."
        }
        Write-Log "$Path\$Name = $actual ($Type) verified." 'SUCCESS'
    } catch {
        $script:Failures++
        Write-Log "Unable to set $Path\$Name : $($_.Exception.Message)" 'ERROR'
    }
}

try { New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null }
catch { Write-Host "ERROR: Cannot create log directory $LogDirectory : $($_.Exception.Message)"; exit 1 }

Write-Log 'Starting Windows Insider restrictions v1.1.0.'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log 'Administrative privileges (or SYSTEM) are required.' 'ERROR'
    exit 1
}

Set-VerifiedRegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PreviewBuilds' -Name 'AllowBuildPreview' -Value 0 -Type DWord
Set-VerifiedRegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -Name 'ManagePreviewBuilds' -Value 1 -Type DWord

$visibilityPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
try {
    if (-not (Test-Path -LiteralPath $visibilityPath)) { New-Item -Path $visibilityPath -Force | Out-Null }
    $existing = [string](Get-ItemProperty -LiteralPath $visibilityPath -Name 'SettingsPageVisibility' -ErrorAction SilentlyContinue).SettingsPageVisibility
    if ([string]::IsNullOrWhiteSpace($existing)) {
        $visibility = 'hide:windowsinsider'
    } elseif ($existing -match '^(?i)hide:(.*)$') {
        $entries = @($Matches[1] -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($entries -notcontains 'windowsinsider') { $entries += 'windowsinsider' }
        $visibility = 'hide:' + ($entries -join ';')
    } elseif ($existing -match '^(?i)showonly:') {
        # A showonly allowlist already excludes pages not named in it.
        # Remove windowsinsider if it is explicitly present, preserving other entries.
        $entries = @($existing.Substring(9) -split ';' | Where-Object { $_ -and $_ -ine 'windowsinsider' })
        if ($entries.Count -eq 0) {
            throw 'Existing showonly list contains only windowsinsider; refusing to replace the allowlist with a hide list.'
        } else {
            $visibility = 'showonly:' + ($entries -join ';')
        }
    } else {
        throw "Unrecognized SettingsPageVisibility format '$existing'; refusing to overwrite existing restrictions."
    }
    Set-VerifiedRegistryValue -Path $visibilityPath -Name 'SettingsPageVisibility' -Value $visibility -Type String
} catch {
    $Failures++
    Write-Log "Settings page restriction failed: $($_.Exception.Message)" 'ERROR'
}

if ($Failures -gt 0) {
    Write-Log "Completed with $Failures failure(s). Review $LogFile" 'ERROR'
    exit 1
}
Write-Log 'All Windows Insider restrictions successfully configured. Close and reopen Settings; a reboot or policy refresh may be needed.' 'SUCCESS'
Write-Log "Log file: $LogFile"
exit 0
