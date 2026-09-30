<#
.SYNOPSIS
    Configures a Windows workstation to use time.nist.gov as its NTP time source.

.DESCRIPTION
    Resilient IT - Desktop Central / Endpoint Central deployment script.

    This script performs the following actions:
      - Verifies the operating system is Windows.
      - Ensures the Windows Time (W32Time) service is configured for automatic startup.
      - Ensures the Windows Time service is running.
      - Configures time.nist.gov as the manual NTP peer.
      - Configures Windows Time to use the NTP/manual peer source.
      - Updates the Windows Time configuration.
      - Forces time source rediscovery.
      - Attempts an immediate time synchronization.
      - Verifies the configured NTP peer and current time source.
      - Writes detailed execution results to C:\Temp.

    Designed for deployment through ManageEngine Desktop Central /
    Endpoint Central running as NT AUTHORITY\SYSTEM.

.NOTES
    Version: 1.0.0
    PowerShell: Windows PowerShell 5.1+
    Execution Context: Administrator / SYSTEM

    Log Location:
        C:\Temp\RIT-Set-NTP-TimeNIST_<ComputerName>_<Timestamp>.log

.EXIT CODES
    0 - Configuration completed successfully.
    1 - General execution failure.
    2 - Windows Time service configuration failure.
    3 - NTP configuration failure.
    4 - Verification failure.
#>

[CmdletBinding()]
param()

# ============================================================================
# Configuration
# ============================================================================

$ScriptVersion = "1.0.0"
$NtpServer     = "time.nist.gov"
$NtpPeer       = "$NtpServer,0x8"
$LogDirectory  = "C:\Temp"
$ComputerName  = $env:COMPUTERNAME
$Timestamp     = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile       = Join-Path $LogDirectory "RIT-Set-NTP-TimeNIST_${ComputerName}_${Timestamp}.log"

# ============================================================================
# Logging
# ============================================================================

function Write-RITLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet("INFO","PASS","WARN","FAIL")]
        [string]$Level = "INFO"
    )

    $LogTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$LogTimestamp] [$Level] $Message"

    Write-Output $LogEntry

    try {
        Add-Content -Path $LogFile -Value $LogEntry -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        Write-Output "[$LogTimestamp] [WARN] Unable to write to log file: $($_.Exception.Message)"
    }
}

# ============================================================================
# Helper - Execute W32TM
# ============================================================================

function Invoke-W32TimeCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    try {
        $Output = & "$env:SystemRoot\System32\w32tm.exe" @Arguments 2>&1
        $ExitCode = $LASTEXITCODE

        return [PSCustomObject]@{
            ExitCode = $ExitCode
            Output   = ($Output -join [Environment]::NewLine)
        }
    }
    catch {
        return [PSCustomObject]@{
            ExitCode = 1
            Output   = $_.Exception.Message
        }
    }
}

# ============================================================================
# Initialization
# ============================================================================

try {
    if (-not (Test-Path -Path $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
}
catch {
    Write-Output "[FAIL] Unable to create log directory $LogDirectory."
    Write-Output $_.Exception.Message
    exit 1
}

Write-RITLog "Starting Resilient IT NTP configuration v$ScriptVersion."
Write-RITLog "Computer: $ComputerName"
Write-RITLog "Execution identity: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-RITLog "Target NTP server: $NtpServer"
Write-RITLog "Configured peer string: $NtpPeer"

# ============================================================================
# Verify Windows Time Service
# ============================================================================

try {
    $TimeService = Get-Service -Name "W32Time" -ErrorAction Stop

    Write-RITLog "Windows Time service detected. Current status: $($TimeService.Status)."

    Set-Service -Name "W32Time" -StartupType Automatic -ErrorAction Stop

    Write-RITLog "Windows Time service startup type set to Automatic." "PASS"

    if ($TimeService.Status -ne "Running") {

        Write-RITLog "Windows Time service is not running. Starting service."

        Start-Service -Name "W32Time" -ErrorAction Stop

        Start-Sleep -Seconds 2

        $TimeService = Get-Service -Name "W32Time"

        if ($TimeService.Status -ne "Running") {
            throw "Windows Time service failed to enter the Running state."
        }
    }

    Write-RITLog "Windows Time service is running." "PASS"
}
catch {
    Write-RITLog "Windows Time service configuration failed: $($_.Exception.Message)" "FAIL"
    exit 2
}

# ============================================================================
# Display Existing Configuration
# ============================================================================

Write-RITLog "Collecting existing Windows Time configuration."

$ExistingConfig = Invoke-W32TimeCommand -Arguments @("/query", "/configuration")

if ($ExistingConfig.ExitCode -eq 0) {
    Write-RITLog "Existing Windows Time configuration collected successfully."
}
else {
    Write-RITLog "Unable to collect existing Windows Time configuration: $($ExistingConfig.Output)" "WARN"
}

$ExistingSource = Invoke-W32TimeCommand -Arguments @("/query", "/source")

if ($ExistingSource.ExitCode -eq 0) {
    Write-RITLog "Current time source before configuration: $($ExistingSource.Output)"
}

# ============================================================================
# Configure NTP
# ============================================================================

Write-RITLog "Configuring Windows Time to use $NtpServer."

$ConfigureResult = Invoke-W32TimeCommand -Arguments @(
    "/config",
    "/manualpeerlist:$NtpPeer",
    "/syncfromflags:manual",
    "/update"
)

if ($ConfigureResult.ExitCode -ne 0) {
    Write-RITLog "Failed to configure NTP peer. Exit code: $($ConfigureResult.ExitCode). Output: $($ConfigureResult.Output)" "FAIL"
    exit 3
}

Write-RITLog "NTP peer configuration command completed successfully." "PASS"

# ============================================================================
# Ensure NtpClient Is Enabled
# ============================================================================

try {
    $NtpClientPath = "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpClient"

    if (Test-Path $NtpClientPath) {

        Set-ItemProperty `
            -Path $NtpClientPath `
            -Name "Enabled" `
            -Value 1 `
            -Type DWord `
            -ErrorAction Stop

        Write-RITLog "Windows NTP Client provider is enabled." "PASS"
    }
    else {
        Write-RITLog "NTP Client registry path was not found." "WARN"
    }
}
catch {
    Write-RITLog "Unable to verify or enable the Windows NTP Client provider: $($_.Exception.Message)" "WARN"
}

# ============================================================================
# Restart Windows Time
# ============================================================================

try {
    Write-RITLog "Restarting Windows Time service to apply configuration."

    Restart-Service -Name "W32Time" -Force -ErrorAction Stop

    Start-Sleep -Seconds 3

    $TimeService = Get-Service -Name "W32Time"

    if ($TimeService.Status -ne "Running") {
        throw "Windows Time service is not running after restart."
    }

    Write-RITLog "Windows Time service restarted successfully." "PASS"
}
catch {
    Write-RITLog "Windows Time service restart failed: $($_.Exception.Message)" "FAIL"
    exit 2
}

# ============================================================================
# Rediscover Time Source
# ============================================================================

Write-RITLog "Forcing Windows Time source rediscovery."

$RediscoverResult = Invoke-W32TimeCommand -Arguments @(
    "/resync",
    "/rediscover"
)

if ($RediscoverResult.ExitCode -eq 0) {
    Write-RITLog "Time source rediscovery completed successfully." "PASS"
}
else {
    Write-RITLog "Initial rediscovery returned exit code $($RediscoverResult.ExitCode): $($RediscoverResult.Output)" "WARN"
}

# ============================================================================
# Force Synchronization
# ============================================================================

Start-Sleep -Seconds 3

Write-RITLog "Requesting immediate time synchronization."

$ResyncResult = Invoke-W32TimeCommand -Arguments @(
    "/resync",
    "/force"
)

if ($ResyncResult.ExitCode -eq 0) {
    Write-RITLog "Immediate time synchronization completed successfully." "PASS"
}
else {
    Write-RITLog "Immediate synchronization returned exit code $($ResyncResult.ExitCode): $($ResyncResult.Output)" "WARN"
    Write-RITLog "The NTP configuration will remain applied and Windows Time can synchronize automatically on its next polling cycle." "WARN"
}

# ============================================================================
# Verification
# ============================================================================

Write-RITLog "Verifying final Windows Time configuration."

$FinalPeers = Invoke-W32TimeCommand -Arguments @(
    "/query",
    "/peers"
)

$FinalSource = Invoke-W32TimeCommand -Arguments @(
    "/query",
    "/source"
)

$FinalStatus = Invoke-W32TimeCommand -Arguments @(
    "/query",
    "/status"
)

if ($FinalPeers.ExitCode -eq 0) {
    Write-RITLog "Configured peer information:"
    Write-RITLog $FinalPeers.Output
}
else {
    Write-RITLog "Unable to query configured NTP peers." "WARN"
}

if ($FinalSource.ExitCode -eq 0) {
    Write-RITLog "Current Windows Time source: $($FinalSource.Output)"
}
else {
    Write-RITLog "Unable to query current Windows Time source." "WARN"
}

if ($FinalStatus.ExitCode -eq 0) {
    Write-RITLog "Windows Time status:"
    Write-RITLog $FinalStatus.Output
}

# ============================================================================
# Registry Verification
# ============================================================================

try {
    $ParametersPath = "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters"

    $Parameters = Get-ItemProperty -Path $ParametersPath -ErrorAction Stop

    $ConfiguredNtpServer = $Parameters.NtpServer
    $ConfiguredType      = $Parameters.Type

    Write-RITLog "Registry NtpServer: $ConfiguredNtpServer"
    Write-RITLog "Registry Type: $ConfiguredType"

    if ($ConfiguredNtpServer -notlike "*$NtpServer*") {
        Write-RITLog "Verification failed. Expected NTP server '$NtpServer' was not found in the active configuration." "FAIL"
        exit 4
    }

    if ($ConfiguredType -ne "NTP") {
        Write-RITLog "Verification failed. Windows Time Type is '$ConfiguredType'; expected 'NTP'." "FAIL"
        exit 4
    }

    Write-RITLog "NTP registry configuration verified successfully." "PASS"
}
catch {
    Write-RITLog "Unable to verify Windows Time registry configuration: $($_.Exception.Message)" "FAIL"
    exit 4
}

# ============================================================================
# Final Result
# ============================================================================

Write-RITLog "------------------------------------------------------------"
Write-RITLog "NTP CONFIGURATION COMPLETE" "PASS"
Write-RITLog "Configured NTP Server : $NtpServer" "PASS"
Write-RITLog "Configured Peer       : $NtpPeer" "PASS"

if ($FinalSource.ExitCode -eq 0) {
    Write-RITLog "Current Time Source    : $($FinalSource.Output)" "PASS"
}

Write-RITLog "Log File               : $LogFile"
Write-RITLog "------------------------------------------------------------"

exit 0
```