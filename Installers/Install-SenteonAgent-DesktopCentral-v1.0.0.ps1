#requires -version 5.1
<#
.SYNOPSIS
    Downloads and installs the Senteon Agent through ManageEngine Desktop Central.

.DESCRIPTION
    Designed for unattended execution as Local SYSTEM. Creates a timestamped
    wrapper log and verbose Windows Installer log under C:\Temp\Senteon.
    Existing installation details are recorded before and after installation.

.NOTES
    Version: 1.0.0
    Run context: Local SYSTEM or an elevated administrator account
    Success exit codes: 0 and 3010 (restart required)
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Organization = 'ORGANIZATION',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Tenant = 'TENANT',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$RegistrationCode = 'REGISTRATION CODE',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$DownloadUri = 'https://update.senteon.co/installers/SenteonAgent.msi',

    [Parameter()]
    [ValidateRange(1, 10)]
    [int]$DownloadAttempts = 3
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:Version = '1.0.0'
$script:RebootRequired = $false
$timeStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$logDirectory = 'C:\Temp\Senteon'
$installerPath = Join-Path $logDirectory 'SenteonAgent.msi'
$wrapperLog = Join-Path $logDirectory ("SenteonAgent_Install_{0}.log" -f $timeStamp)
$msiLog = Join-Path $logDirectory ("SenteonAgent_MSI_{0}.log" -f $timeStamp)

function Write-RITLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Output $line
    try {
        Add-Content -LiteralPath $wrapperLog -Value $line -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        Write-Output "Unable to write to wrapper log: $($_.Exception.Message)"
    }
}

function Get-SenteonInstallation {
    [CmdletBinding()]
    param()

    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $matches = foreach ($root in $uninstallRoots) {
        Get-ItemProperty -Path $root -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like '*Senteon*' } |
            Select-Object DisplayName, DisplayVersion, Publisher, InstallDate, PSChildName
    }

    return @($matches | Sort-Object DisplayName, DisplayVersion -Unique)
}

function Get-DownloadedInstaller {
    [CmdletBinding()]
    param()

    if (Test-Path -LiteralPath $installerPath) {
        Remove-Item -LiteralPath $installerPath -Force -ErrorAction Stop
    }

    for ($attempt = 1; $attempt -le $DownloadAttempts; $attempt++) {
        try {
            Write-RITLog "Downloading Senteon Agent installer (attempt $attempt of $DownloadAttempts)."
            Invoke-WebRequest -Uri $DownloadUri -UseBasicParsing -OutFile $installerPath -TimeoutSec 120

            $file = Get-Item -LiteralPath $installerPath -ErrorAction Stop
            if ($file.Length -lt 102400) {
                throw "Downloaded file is unexpectedly small ($($file.Length) bytes)."
            }

            $signature = Get-AuthenticodeSignature -FilePath $installerPath
            if ($signature.Status -ne 'Valid') {
                throw "Installer signature validation failed. Status: $($signature.Status)."
            }

            $hash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash
            Write-RITLog "Download completed. Size: $($file.Length) bytes; SHA256: $hash; signer: $($signature.SignerCertificate.Subject)." 'SUCCESS'
            return
        }
        catch {
            Write-RITLog "Download attempt $attempt failed: $($_.Exception.Message)" 'WARNING'
            Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
            if ($attempt -lt $DownloadAttempts) {
                Start-Sleep -Seconds (5 * $attempt)
            }
        }
    }

    throw "Unable to download a valid Senteon Agent installer after $DownloadAttempts attempts."
}

try {
    if (-not (Test-Path -LiteralPath $logDirectory)) {
        New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
    }

    Write-RITLog "Starting Senteon Agent deployment script v$script:Version."
    Write-RITLog "Computer: $env:COMPUTERNAME; identity: $([Security.Principal.WindowsIdentity]::GetCurrent().Name); tenant: $Tenant; organization: $Organization."

    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Administrative rights are required. Configure Desktop Central to run this deployment as SYSTEM.'
    }

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    }
    catch {
        Write-RITLog "Could not explicitly set TLS 1.2: $($_.Exception.Message)" 'WARNING'
    }

    $before = @(Get-SenteonInstallation)
    if ($before.Count -gt 0) {
        foreach ($item in $before) {
            Write-RITLog "Existing installation detected: $($item.DisplayName), version $($item.DisplayVersion)."
        }
    }
    else {
        Write-RITLog 'No existing Senteon installation was detected.'
    }

    Get-DownloadedInstaller

    $msiArguments = @(
        '/i'
        ('"{0}"' -f $installerPath)
        '/qn'
        '/norestart'
        ('ORGANIZATION="{0}"' -f $Organization)
        ('TENANT="{0}"' -f $Tenant)
        ('REGISTRATIONCODE="{0}"' -f $RegistrationCode)
        'ACCEPTALL=YES'
        '/l*v'
        ('"{0}"' -f $msiLog)
    )

    Write-RITLog 'Launching Windows Installer. Sensitive registration data is intentionally omitted from this log.'
    $process = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" -ArgumentList $msiArguments -Wait -PassThru -WindowStyle Hidden
    Write-RITLog "Windows Installer returned exit code $($process.ExitCode)."

    switch ($process.ExitCode) {
        0 { }
        1641 { $script:RebootRequired = $true }
        3010 { $script:RebootRequired = $true }
        default { throw "Senteon Agent installation failed with Windows Installer exit code $($process.ExitCode). Review $msiLog." }
    }

    Start-Sleep -Seconds 5
    $after = @(Get-SenteonInstallation)
    if ($after.Count -eq 0) {
        throw "Windows Installer reported success, but Senteon was not found in the installed-program registry. Review $msiLog."
    }

    foreach ($item in $after) {
        Write-RITLog "Verified installation: $($item.DisplayName), version $($item.DisplayVersion)." 'SUCCESS'
    }

    $senteonServices = @(Get-Service -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -like '*Senteon*' -or $_.DisplayName -like '*Senteon*'
    })
    if ($senteonServices.Count -gt 0) {
        foreach ($service in $senteonServices) {
            Write-RITLog "Service verification: $($service.Name) [$($service.Status)]."
        }
    }
    else {
        Write-RITLog 'No Windows service containing Senteon in its name was found; registry installation verification succeeded.' 'WARNING'
    }

    if ($script:RebootRequired) {
        Write-RITLog "Senteon Agent installed successfully; Windows Installer requested a restart. MSI log: $msiLog" 'SUCCESS'
        exit 3010
    }

    Write-RITLog "Senteon Agent installed and verified successfully. MSI log: $msiLog" 'SUCCESS'
    exit 0
}
catch {
    Write-RITLog "Deployment failed: $($_.Exception.Message)" 'ERROR'
    Write-RITLog "Wrapper log: $wrapperLog; MSI log (if created): $msiLog" 'ERROR'
    exit 1
}
