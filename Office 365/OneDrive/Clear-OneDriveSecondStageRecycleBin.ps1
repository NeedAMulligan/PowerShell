<#
.SYNOPSIS
    Permanently deletes items from the SECOND-STAGE recycle bin of a OneDrive for Business site.

.DESCRIPTION
    Connects to a OneDrive for Business site using PnP PowerShell via PowerShell 7 and repeatedly:
      1. Retrieves up to BatchSize items from the second-stage recycle bin.
      2. Permanently deletes those items using SharePoint REST DeleteByIds.
      3. Logs each batch to C:\Temp.
      4. Repeats until the second-stage recycle bin is empty.

    IMPORTANT:
      - Deletion from the second-stage recycle bin is permanent.
      - The signed-in account must have sufficient rights to the OneDrive site.
      - Modern PnP PowerShell interactive authentication requires your own Entra ID
        application Client ID.

.EXAMPLE
    .\Clear-OneDriveSecondStageRecycleBin-v1.0.1.ps1 `
        -ClientId "00000000-0000-0000-0000-000000000000"

.EXAMPLE
    .\Clear-OneDriveSecondStageRecycleBin-v1.0.1.ps1 `
        -ClientId "00000000-0000-0000-0000-000000000000" `
        -BatchSize 100 `
        -Force

.NOTES
    Output/log location:
        C:\Temp\OneDrive-SecondStage-Purge-<timestamp>.log
        C:\Temp\OneDrive-SecondStage-Purge-<timestamp>.csv
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OneDriveUrl = 'https://COMPANYNAME-my.sharepoint.com/personal/USERNAME_COMPANYDOMAIN_com',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ClientId = "CLIENT-ID",

    [Parameter()]
    [ValidateRange(1, 100)]
    [int]$BatchSize = 100,

    [Parameter()]
    [ValidateRange(0, 60)]
    [int]$PauseSeconds = 2,

    [Parameter()]
    [ValidateRange(1, 10)]
    [int]$MaxRetries = 5,

    [Parameter()]
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
$LogRoot = 'C:\Temp'
if (-not (Test-Path -LiteralPath $LogRoot)) {
    New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null
}

$TimeStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogRoot "OneDrive-SecondStage-Purge-$TimeStamp.log"
$CsvFile = Join-Path $LogRoot "OneDrive-SecondStage-Purge-$TimeStamp.csv"

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO','SUCCESS','WARNING','ERROR')]
        [string]$Level = 'INFO'
    )

    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -LiteralPath $LogFile -Value $line

    switch ($Level) {
        'SUCCESS' { Write-Host $line -ForegroundColor Green }
        'WARNING' { Write-Host $line -ForegroundColor Yellow }
        'ERROR'   { Write-Host $line -ForegroundColor Red }
        default   { Write-Host $line }
    }
}

function Export-Result {
    param(
        [Parameter(Mandatory)]
        [object[]]$Items,

        [Parameter(Mandatory)]
        [int]$BatchNumber,

        [Parameter(Mandatory)]
        [string]$Status,

        [string]$ErrorMessage = ''
    )

    foreach ($item in $Items) {
        [pscustomobject]@{
            Timestamp    = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            Batch        = $BatchNumber
            Id           = $item.Id
            Title        = $item.Title
            LeafName     = $item.LeafName
            ItemType     = $item.ItemType
            DeletedDate  = $item.DeletedDate
            DeletedBy    = $item.DeletedByEmail
            Status       = $Status
            ErrorMessage = $ErrorMessage
        } | Export-Csv -LiteralPath $CsvFile -NoTypeInformation -Append
    }
}

# ---------------------------------------------------------------------------
# Validate prerequisites
# ---------------------------------------------------------------------------
if (-not (Get-Module -ListAvailable -Name PnP.PowerShell)) {
    throw @"
PnP.PowerShell is not installed.

Install it from an elevated PowerShell 7 session with:
    Install-Module PnP.PowerShell -Scope CurrentUser

Then rerun this script.
"@
}

Import-Module PnP.PowerShell -ErrorAction Stop

Write-Log "Starting OneDrive second-stage recycle bin purge."
Write-Log "OneDrive URL: $OneDriveUrl"
Write-Log "PnP Client ID: $ClientId"
Write-Log "Batch size: $BatchSize"
Write-Log "Pause between batches: $PauseSeconds second(s)"
Write-Log "Log file: $LogFile"
Write-Log "CSV result file: $CsvFile"

# ---------------------------------------------------------------------------
# Explicit safety confirmation
# ---------------------------------------------------------------------------
if (-not $Force) {
    Write-Host ""
    Write-Host "WARNING: This permanently deletes items from the SECOND-STAGE recycle bin." -ForegroundColor Red
    Write-Host "These items cannot be restored from the OneDrive/SharePoint recycle bin after deletion." -ForegroundColor Red
    Write-Host ""
    Write-Host "Target: $OneDriveUrl" -ForegroundColor Yellow
    Write-Host ""

    $confirmation = Read-Host "Type PURGE to continue"

    if ($confirmation -cne 'PURGE') {
        Write-Log "Operation cancelled by user." 'WARNING'
        return
    }
}

# ---------------------------------------------------------------------------
# Connect
# ---------------------------------------------------------------------------
try {
    Write-Log "Connecting to OneDrive using interactive PnP authentication..."
    $connection = Connect-PnPOnline `
        -Url $OneDriveUrl `
        -Interactive `
        -ClientId $ClientId `
        -ReturnConnection

    Write-Log "Connected successfully." 'SUCCESS'
}
catch {
    Write-Log "Connection failed: $($_.Exception.Message)" 'ERROR'
    throw
}

# ---------------------------------------------------------------------------
# Delete function
# ---------------------------------------------------------------------------
function Remove-SecondStageBatch {
    param(
        [Parameter(Mandatory)]
        [object[]]$Items,

        [Parameter(Mandatory)]
        [int]$BatchNumber
    )

    $apiUrl = '/_api/site/RecycleBin/DeleteByIds'
    $idValues = @($Items | ForEach-Object { $_.Id.ToString() })
    $idsString = $idValues -join "','"
    $body = "{'ids':['$idsString']}"

    $attempt = 0

    while ($attempt -lt $MaxRetries) {
        $attempt++

        try {
            Write-Log "Batch ${BatchNumber}: deleting $($Items.Count) item(s), attempt $attempt of $MaxRetries."

            Invoke-PnPSPRestMethod `
                -Method Post `
                -Url $apiUrl `
                -Content $body `
                -ContentType 'application/json;odata=verbose' `
                -Connection $connection | Out-Null

            Export-Result `
                -Items $Items `
                -BatchNumber $BatchNumber `
                -Status 'Deleted'

            Write-Log "Batch ${BatchNumber}: successfully deleted $($Items.Count) item(s)." 'SUCCESS'
            return $true
        }
        catch {
            $message = $_.Exception.Message
            Write-Log "Batch ${BatchNumber} attempt $attempt failed: $message" 'WARNING'

            if ($attempt -ge $MaxRetries) {
                Export-Result `
                    -Items $Items `
                    -BatchNumber $BatchNumber `
                    -Status 'Failed' `
                    -ErrorMessage $message

                Write-Log "Batch ${BatchNumber} failed after $MaxRetries attempts." 'ERROR'
                return $false
            }

            # Exponential backoff: 5, 10, 20, 40... seconds
            $delay = [Math]::Min(120, (5 * [Math]::Pow(2, ($attempt - 1))))
            Write-Log "Waiting $delay second(s) before retry."
            Start-Sleep -Seconds $delay
        }
    }

    return $false
}

# ---------------------------------------------------------------------------
# Main purge loop
# ---------------------------------------------------------------------------
$batchNumber = 0
$totalDeleted = 0
$consecutiveNoProgress = 0
$startTime = Get-Date

try {
    while ($true) {
        Write-Log "Querying up to $BatchSize item(s) from the second-stage recycle bin..."

        $items = @(
            Get-PnPRecycleBinItem `
                -SecondStage `
                -RowLimit $BatchSize `
                -Connection $connection
        )

        if ($items.Count -eq 0) {
            Write-Log "Second-stage recycle bin is empty." 'SUCCESS'
            break
        }

        $batchNumber++
        Write-Log "Batch ${batchNumber} retrieved $($items.Count) item(s)."

        $beforeIds = @($items | ForEach-Object { $_.Id.ToString() })

        $success = Remove-SecondStageBatch `
            -Items $items `
            -BatchNumber $batchNumber

        if (-not $success) {
            throw "Batch $batchNumber could not be deleted after $MaxRetries attempts. Review $LogFile and $CsvFile."
        }

        $totalDeleted += $items.Count

        Write-Host ""
        Write-Host ("Progress: {0:N0} item(s) permanently deleted so far." -f $totalDeleted) -ForegroundColor Cyan
        Write-Host ""

        if ($PauseSeconds -gt 0) {
            Start-Sleep -Seconds $PauseSeconds
        }

        # Confirm that SharePoint is advancing rather than returning the same batch
        $verificationItems = @(
            Get-PnPRecycleBinItem `
                -SecondStage `
                -RowLimit $BatchSize `
                -Connection $connection
        )

        if ($verificationItems.Count -eq 0) {
            Write-Log "Verification confirms the second-stage recycle bin is empty." 'SUCCESS'
            break
        }

        $afterIds = @($verificationItems | ForEach-Object { $_.Id.ToString() })
        $sameIds = @($beforeIds | Where-Object { $afterIds -contains $_ })

        if ($sameIds.Count -eq $beforeIds.Count -and $beforeIds.Count -gt 0) {
            $consecutiveNoProgress++
            Write-Log "SharePoint returned the same batch after deletion. No-progress check $consecutiveNoProgress of 3." 'WARNING'

            if ($consecutiveNoProgress -ge 3) {
                throw "No progress detected across 3 verification checks. Stopping to avoid an endless loop. Review the recycle bin and logs."
            }

            Start-Sleep -Seconds 10
        }
        else {
            $consecutiveNoProgress = 0
        }
    }
}
catch {
    Write-Log "Purge stopped: $($_.Exception.Message)" 'ERROR'
    throw
}
finally {
    try {
        Disconnect-PnPOnline -Connection $connection -ErrorAction SilentlyContinue
    }
    catch {
        # Ignore disconnect errors
    }
}

$elapsed = (Get-Date) - $startTime

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " OneDrive Second-Stage Recycle Bin Purge Complete" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ("Total deleted : {0:N0}" -f $totalDeleted)
Write-Host ("Batches       : {0:N0}" -f $batchNumber)
Write-Host ("Elapsed       : {0:hh\:mm\:ss}" -f $elapsed)
Write-Host "Log           : $LogFile"
Write-Host "Results CSV   : $CsvFile"
Write-Host ""

Write-Log ("Completed. Permanently deleted {0:N0} item(s) in {1:N0} batch(es)." -f $totalDeleted, $batchNumber) 'SUCCESS'
