#requires -Version 5.1

<#
.SYNOPSIS
    Filters Windows Event Viewer records and exports them to a timestamped CSV file.

.DESCRIPTION
    Queries one Windows event log using an event source/provider and a configurable
    lookback period. Optional Event ID, severity, and message keyword filters are
    supported. Output and execution logs are written to C:\Temp by default.

    The defaults export Application log events from the "Senteon Agent" source
    for the previous seven days.

.PARAMETER LogName
    The Event Viewer log that contains the events.

    Where to find it:
      Event Viewer > Windows Logs > select the applicable log.

    Enter the log name exactly as Windows displays it. Common values:
      Application     Application and third-party software events
      System          Windows services, drivers, startup, and hardware events
      Security        Sign-in, account, and audit events (administrator required)
      Setup           Windows installation and servicing events
      ForwardedEvents Events collected from other computers

    Default: Application

.PARAMETER ProviderName
    The event Source shown in Event Viewer. PowerShell calls this ProviderName.

    Where to find it:
      Open an event and use the value beside "Source" on the General tab, or
      review the "Source" column in the event list.

    Enter the source exactly, including spaces. Examples:
      Senteon Agent
      Service Control Manager
      Microsoft-Windows-WindowsUpdateClient

    Default: Senteon Agent

.PARAMETER DaysBack
    Whole number of days to search backward from the time the script starts.
    This value is in DAYS, not seconds.

    Examples:
      1  = previous 24 hours
      7  = previous 7 days (168 hours / 604800 seconds)
      30 = previous 30 days

    Default: 7

.PARAMETER EventId
    Optional numeric Event ID or comma-separated list of Event IDs.

    Where to find it:
      Open an event and locate "Event ID" on the General or Details tab.

    Examples:
      -EventId 100
      -EventId 100,101,102

    Omit this parameter to include all Event IDs from the selected source.

.PARAMETER Level
    Optional severity level or comma-separated list of levels. Accepted values:
      Critical
      Error
      Warning
      Information
      Verbose

    Examples:
      -Level Error
      -Level Critical,Error,Warning

    Omit this parameter to include every severity level.

.PARAMETER MessageKeyword
    Optional word or phrase that must appear in the event's General message.
    The search is not case-sensitive and partial matches are accepted.

    Examples:
      -MessageKeyword 'failed'
      -MessageKeyword 'configuration applied'

    Omit this parameter to include events regardless of message text.

.PARAMETER OutputFolder
    Full Windows folder path for the CSV report and execution log. The script
    creates the folder when it does not exist.

    Example: C:\Temp
    Default: C:\Temp

.EXAMPLE
    .\Export-WindowsEventLog-Template-v1.1.0.ps1

    Exports Senteon Agent events from Application for the previous seven days.

.EXAMPLE
    .\Export-WindowsEventLog-Template-v1.1.0.ps1 -ProviderName 'Senteon Agent' -DaysBack 14 -EventId 100,101

.EXAMPLE
    .\Export-WindowsEventLog-Template-v1.1.0.ps1 -LogName System -ProviderName 'Service Control Manager' -DaysBack 3 -Level Error,Warning

.EXAMPLE
    .\Export-WindowsEventLog-Template-v1.1.0.ps1 -ProviderName 'Senteon Agent' -DaysBack 7 -MessageKeyword 'failed'

.EXAMPLE
    Get-WinEvent -ListLog * | Select-Object LogName, RecordCount

    Lists available logs when the correct LogName is unknown.

.EXAMPLE
    Get-WinEvent -ListProvider *Senteon* | Select-Object Name

    Finds the exact registered provider name when the Event Viewer Source is unknown.

.NOTES
    Version: 1.1.0
    Run as Administrator when querying protected logs such as Security.

    QUICK PARAMETER REFERENCE
    -------------------------
    LogName        = Event Viewer log, such as Application or System
    ProviderName   = Event Viewer Source, such as Senteon Agent
    DaysBack       = Search period in whole days; 7 means 604800 seconds
    EventId        = Optional numeric event identifier(s)
    Level          = Optional event severity name(s)
    MessageKeyword = Optional text found within the event message
    OutputFolder   = Full folder path for CSV and execution-log files
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$LogName = 'Application', # Event Viewer log name; for example: Application or System

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ProviderName = 'Senteon Agent', # Event Viewer "Source" value; enter it exactly

    [Parameter()]
    [ValidateRange(1, 3650)]
    [int]$DaysBack = 7, # Time window in whole DAYS; 7 days = 604800 seconds

    [Parameter()]
    [ValidateRange(0, 65535)]
    [int[]]$EventId, # Optional numeric ID(s); for example: 100 or 100,101,102

    [Parameter()]
    [ValidateSet('Critical', 'Error', 'Warning', 'Information', 'Verbose')]
    [string[]]$Level, # Optional severity name(s); omit to export every level

    [Parameter()]
    [string]$MessageKeyword, # Optional case-insensitive text from the event message

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputFolder = 'C:\Temp' # Full destination folder; created automatically
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:ExecutionLog = $null

$levelMap = @{
    Critical    = 1
    Error       = 2
    Warning     = 3
    Information = 4
    Verbose     = 5
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $entry = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $entry
    Add-Content -LiteralPath $script:ExecutionLog -Value $entry -Encoding UTF8
}

try {
    if (-not (Test-Path -LiteralPath $OutputFolder)) {
        $null = New-Item -Path $OutputFolder -ItemType Directory -Force
    }

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $safeProvider = ($ProviderName -replace '[^a-zA-Z0-9._-]', '-') -replace '-+', '-'
    $safeLogName = ($LogName -replace '[^a-zA-Z0-9._-]', '-') -replace '-+', '-'
    $baseName = '{0}_{1}_Last-{2}-Days_{3}' -f $safeLogName, $safeProvider, $DaysBack, $timestamp
    $exportPath = Join-Path -Path $OutputFolder -ChildPath ($baseName + '.csv')
    $script:ExecutionLog = Join-Path -Path $OutputFolder -ChildPath ($baseName + '_Execution.log')

    Write-Log -Message "Starting event export from '$LogName'."
    Write-Log -Message "Provider: '$ProviderName'; Lookback: $DaysBack day(s)."

    $filter = @{
        LogName      = $LogName
        ProviderName = $ProviderName
        StartTime    = (Get-Date).AddDays(-$DaysBack)
    }

    if ($EventId -and $EventId.Count -gt 0) {
        $filter.Id = $EventId
        Write-Log -Message ('Event IDs: {0}' -f ($EventId -join ', '))
    }

    if ($Level -and $Level.Count -gt 0) {
        $filter.Level = @($Level | ForEach-Object { $levelMap[$_] })
        Write-Log -Message ('Levels: {0}' -f ($Level -join ', '))
    }

    $events = @(Get-WinEvent -FilterHashtable $filter -ErrorAction Stop)

    if (-not [string]::IsNullOrWhiteSpace($MessageKeyword)) {
        Write-Log -Message "Applying message keyword filter: '$MessageKeyword'."
        $events = @($events | Where-Object { $_.Message -like ('*{0}*' -f $MessageKeyword) })
    }

    if ($events.Count -eq 0) {
        Write-Log -Message 'No matching events were found. No CSV file was created.' -Level WARNING
        exit 0
    }

    $events |
        Sort-Object -Property TimeCreated -Descending |
        Select-Object -Property TimeCreated,
            MachineName,
            LogName,
            ProviderName,
            Id,
            LevelDisplayName,
            TaskDisplayName,
            OpcodeDisplayName,
            RecordId,
            UserId,
            ProcessId,
            ThreadId,
            Message |
        Export-Csv -LiteralPath $exportPath -NoTypeInformation -Encoding UTF8

    Write-Log -Message ("Exported {0} event(s) to: {1}" -f $events.Count, $exportPath) -Level SUCCESS
}
catch {
    $errorText = $_.Exception.Message

    if ($errorText -like '*No events were found that match*') {
        Write-Log -Message 'No matching events were found. No CSV file was created.' -Level WARNING
        exit 0
    }
    elseif ($script:ExecutionLog) {
        Write-Log -Message $errorText -Level ERROR
    }
    else {
        Write-Error $errorText
    }

    exit 1
}
