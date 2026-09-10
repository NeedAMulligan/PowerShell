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
    Event log to query. Examples: Application, System, Security, Setup.

.PARAMETER ProviderName
    Event Viewer source/provider name. The value must match the registered provider.

.PARAMETER DaysBack
    Number of days to include, counting backward from the script start time.

.PARAMETER EventId
    Optional list of Event IDs. Leave empty to include every Event ID.

.PARAMETER Level
    Optional event levels: Critical, Error, Warning, Information, Verbose.
    Leave empty to include all levels.

.PARAMETER MessageKeyword
    Optional text to find in the rendered event message. This filter is applied
    after Windows returns the events.

.PARAMETER OutputFolder
    Folder used for the CSV export and execution log.

.EXAMPLE
    .\Export-WindowsEventLog-Template-v1.0.0.ps1

    Exports Senteon Agent events from Application for the previous seven days.

.EXAMPLE
    .\Export-WindowsEventLog-Template-v1.0.0.ps1 -ProviderName 'Senteon Agent' -DaysBack 14 -EventId 100,101

.EXAMPLE
    .\Export-WindowsEventLog-Template-v1.0.0.ps1 -LogName System -ProviderName 'Service Control Manager' -DaysBack 3 -Level Error,Warning

.NOTES
    Version: 1.0.0
    Run as Administrator when querying protected logs such as Security.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$LogName = 'Application',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ProviderName = 'Senteon Agent',

    [Parameter()]
    [ValidateRange(1, 3650)]
    [int]$DaysBack = 7,

    [Parameter()]
    [ValidateRange(0, 65535)]
    [int[]]$EventId,

    [Parameter()]
    [ValidateSet('Critical', 'Error', 'Warning', 'Information', 'Verbose')]
    [string[]]$Level,

    [Parameter()]
    [string]$MessageKeyword,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputFolder = 'C:\Temp'
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
