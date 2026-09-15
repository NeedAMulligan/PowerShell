#requires -Version 5.1

<#
.SYNOPSIS
    Triggers and validates Microsoft Entra hybrid join on a Windows endpoint.

.DESCRIPTION
    Designed for ManageEngine Desktop Central / Endpoint Central execution as
    Local System. The script validates domain membership, enables and starts
    the built-in Automatic-Device-Join task, polls dsregcmd.exe, and writes a
    timestamped transcript to C:\Temp by default.

    This script does not run dsregcmd.exe /leave, delete certificates, remove
    device objects, restart Windows, or start an Entra Connect sync cycle.

.PARAMETER LogPath
    Directory used for the timestamped transcript.

.PARAMETER WaitSeconds
    Maximum number of seconds to wait for hybrid join to complete.

.PARAMETER PollSeconds
    Number of seconds between validation attempts.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Invoke-EntraHybridJoin.ps1

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Invoke-EntraHybridJoin.ps1 -WaitSeconds 300 -PollSeconds 15

.NOTES
    Requires: Windows PowerShell 5.1, administrator or Local System context
    Exit code 0: PASS - device is Microsoft Entra hybrid joined and authenticated
    Exit code 1: WARNING - task was triggered, but registration is still pending
    Exit code 2: FAIL - prerequisite, task, or execution failure
#>

[CmdletBinding()]
param (
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$LogPath = 'C:\Temp',

    [Parameter()]
    [ValidateRange(30, 1800)]
    [int]$WaitSeconds = 300,

    [Parameter()]
    [ValidateRange(5, 300)]
    [int]$PollSeconds = 15
)

#region CLIENT VARIABLES
$ScriptName = 'Invoke-EntraHybridJoin'
$ComputerName = $env:COMPUTERNAME
$TimeStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$TranscriptPath = Join-Path -Path $LogPath -ChildPath "${ScriptName}_${ComputerName}_${TimeStamp}.log"
$TaskPath = '\Microsoft\Windows\Workplace Join\'
$TaskName = 'Automatic-Device-Join'
$script:ExitCode = 2
$script:TranscriptStarted = $false
#endregion CLIENT VARIABLES

#region FUNCTIONS
function Write-Status {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateSet('PASS', 'FAIL', 'WARN', 'INFO')]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Message
    )

    $Line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Output $Line
}

function Test-IsAdministrator {
    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
    return $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-DsRegValue {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string[]]$Output,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $Match = $Output | Select-String -Pattern ('^\s*{0}\s*:\s*(.+?)\s*$' -f [regex]::Escape($Name)) | Select-Object -First 1
    if ($Match) {
        return $Match.Matches[0].Groups[1].Value.Trim()
    }

    return $null
}

function Get-HybridJoinState {
    $DsRegOutput = & "$env:SystemRoot\System32\dsregcmd.exe" /status 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "dsregcmd.exe returned exit code $LASTEXITCODE."
    }

    [PSCustomObject]@{
        AzureAdJoined   = Get-DsRegValue -Output $DsRegOutput -Name 'AzureAdJoined'
        DomainJoined    = Get-DsRegValue -Output $DsRegOutput -Name 'DomainJoined'
        DeviceAuthStatus = Get-DsRegValue -Output $DsRegOutput -Name 'DeviceAuthStatus'
        DeviceId        = Get-DsRegValue -Output $DsRegOutput -Name 'DeviceId'
        ErrorPhase      = Get-DsRegValue -Output $DsRegOutput -Name 'Error Phase'
        ClientErrorCode = Get-DsRegValue -Output $DsRegOutput -Name 'Client ErrorCode'
        ServerErrorCode = Get-DsRegValue -Output $DsRegOutput -Name 'Server ErrorCode'
        ServerErrorSubCode = Get-DsRegValue -Output $DsRegOutput -Name 'Server ErrorSubCode'
    }
}

function Test-HybridJoinComplete {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [psobject]$State
    )

    return (
        $State.AzureAdJoined -eq 'YES' -and
        $State.DomainJoined -eq 'YES' -and
        $State.DeviceAuthStatus -eq 'SUCCESS'
    )
}
#endregion FUNCTIONS

#region EXECUTION
try {
    # Desktop Central may launch 32-bit PowerShell on a 64-bit endpoint.
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        $SysnativePowerShell = Join-Path $env:WINDIR 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
        if (-not (Test-Path -LiteralPath $SysnativePowerShell)) {
            throw 'Unable to locate 64-bit Windows PowerShell through Sysnative.'
        }

        $RelaunchArguments = @(
            '-NoProfile'
            '-NonInteractive'
            '-ExecutionPolicy', 'Bypass'
            '-File', ('"{0}"' -f $PSCommandPath)
            '-LogPath', ('"{0}"' -f $LogPath)
            '-WaitSeconds', $WaitSeconds
            '-PollSeconds', $PollSeconds
        )

        $Process = Start-Process -FilePath $SysnativePowerShell -ArgumentList $RelaunchArguments -Wait -PassThru
        exit $Process.ExitCode
    }

    if (-not (Test-Path -LiteralPath $LogPath)) {
        New-Item -Path $LogPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    Start-Transcript -Path $TranscriptPath -Force -ErrorAction Stop | Out-Null
    $script:TranscriptStarted = $true

    Write-Status -Level INFO -Message "Starting Microsoft Entra hybrid-join trigger on $ComputerName."
    Write-Status -Level INFO -Message "Running as $([Security.Principal.WindowsIdentity]::GetCurrent().Name); 64-bit process: $([Environment]::Is64BitProcess)."
    Write-Status -Level INFO -Message "Transcript: $TranscriptPath"

    if (-not (Test-IsAdministrator)) {
        throw 'Administrative or Local System rights are required.'
    }

    $ComputerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    if (-not $ComputerSystem.PartOfDomain) {
        throw 'The computer is not joined to an Active Directory domain.'
    }

    Write-Status -Level PASS -Message "Domain membership confirmed: $($ComputerSystem.Domain)."

    $InitialState = Get-HybridJoinState
    Write-Status -Level INFO -Message "Initial state: AzureAdJoined=$($InitialState.AzureAdJoined); DomainJoined=$($InitialState.DomainJoined); DeviceAuthStatus=$($InitialState.DeviceAuthStatus)."

    if (Test-HybridJoinComplete -State $InitialState) {
        Write-Status -Level PASS -Message "Device is already Microsoft Entra hybrid joined. DeviceId=$($InitialState.DeviceId)."
        $script:ExitCode = 0
    }
    else {
        $Task = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop

        if ($Task.State -eq 'Disabled') {
            Enable-ScheduledTask -InputObject $Task -ErrorAction Stop | Out-Null
            Write-Status -Level INFO -Message 'Enabled the Automatic-Device-Join scheduled task.'
        }

        Start-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop
        Write-Status -Level INFO -Message "Triggered $TaskPath$TaskName."

        $Deadline = (Get-Date).AddSeconds($WaitSeconds)
        $CurrentState = $InitialState

        do {
            Start-Sleep -Seconds $PollSeconds
            $CurrentState = Get-HybridJoinState
            Write-Status -Level INFO -Message "Current state: AzureAdJoined=$($CurrentState.AzureAdJoined); DomainJoined=$($CurrentState.DomainJoined); DeviceAuthStatus=$($CurrentState.DeviceAuthStatus)."
        } until ((Test-HybridJoinComplete -State $CurrentState) -or (Get-Date) -ge $Deadline)

        if (Test-HybridJoinComplete -State $CurrentState) {
            Write-Status -Level PASS -Message "Microsoft Entra hybrid join completed successfully. DeviceId=$($CurrentState.DeviceId)."
            $script:ExitCode = 0
        }
        else {
            $Diagnostic = @(
                "ErrorPhase=$($CurrentState.ErrorPhase)"
                "ClientErrorCode=$($CurrentState.ClientErrorCode)"
                "ServerErrorCode=$($CurrentState.ServerErrorCode)"
                "ServerErrorSubCode=$($CurrentState.ServerErrorSubCode)"
            ) -join '; '

            Write-Status -Level WARN -Message "Registration remains pending after $WaitSeconds seconds. $Diagnostic"
            Write-Status -Level INFO -Message 'If the Entra hybrid device object is Pending, run an Entra Connect delta sync and trigger this script again.'
            $script:ExitCode = 1
        }
    }
}
catch {
    Write-Status -Level FAIL -Message $_.Exception.Message
    $script:ExitCode = 2
}
finally {
    Write-Status -Level INFO -Message "Completed with exit code $script:ExitCode."

    if ($script:TranscriptStarted) {
        try {
            Stop-Transcript | Out-Null
        }
        catch {
            Write-Output "[WARN] Unable to stop transcript cleanly: $($_.Exception.Message)"
        }
    }
}

exit $script:ExitCode
#endregion EXECUTION
