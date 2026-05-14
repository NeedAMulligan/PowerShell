<#
.SYNOPSIS
    Comprehensive Azure AD Connect (ADSync) backup script with fallback support.

.DESCRIPTION
    This script performs a robust backup of Azure AD Connect configuration.
    It attempts to use the modern export cmdlet if available. If not, it falls
    back to collecting all critical configuration components individually.

    Output is stored in:
    C:\temp\ADSync-Backup-<CLIENTNAME>-<YYMMDD>

    Script runs silently and logs to C:\temp.

.EXITCODES
    0 = Success
    1 = General failure
    2 = ADSync module not found
    3 = Service failure
    4 = Export failure
    5 = Validation failure

.EXAMPLE
    .\Backup-ADSync.ps1
#>

#region Variables
$ScriptName   = "Backup-ADSync"
$LogPath      = "C:\temp"
$BackupRoot   = "C:\temp"
$DateStamp    = Get-Date -Format "yyMMdd"
$TimeStamp    = Get-Date -Format "yyyyMMdd_HHmmss"
$ComputerName = $env:COMPUTERNAME
$BackupFolder = Join-Path $BackupRoot "ADSync-Backup-$ComputerName-$DateStamp"
$LogFile      = Join-Path $LogPath "$ScriptName`_$TimeStamp.log"
$ZipFile      = "$BackupFolder.zip"
#endregion

#region Logging
function Write-Log {
    param ([string]$Message,[string]$Level="INFO")
    $Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Time [$Level] $Message" | Out-File -FilePath $LogFile -Append -Encoding utf8
}
#endregion

#region Prechecks
function Test-ADSyncModule {
    try {
        if (-not (Get-Module -ListAvailable -Name ADSync)) {
            Write-Log "ADSync module not found." "ERROR"
            exit 2
        }
        Import-Module ADSync -ErrorAction Stop
        Write-Log "ADSync module loaded."
    } catch {
        Write-Log "Failed to load ADSync module: $_" "ERROR"
        exit 2
    }
}

function Ensure-Service {
    try {
        $svc = Get-Service ADSync -ErrorAction Stop
        if ($svc.Status -ne "Running") {
            Write-Log "Starting ADSync service..."
            Start-Service ADSync -ErrorAction Stop
            Start-Sleep 10
            $svc.Refresh()
            if ($svc.Status -ne "Running") {
                Write-Log "Service failed to start." "ERROR"
                exit 3
            }
        }
        Write-Log "ADSync service running."
    } catch {
        Write-Log "Service check failed: $_" "ERROR"
        exit 3
    }
}
#endregion

#region Backup Functions
function New-BackupFolder {
    try {
        New-Item -Path $BackupFolder -ItemType Directory -Force | Out-Null
        Write-Log "Backup folder created: $BackupFolder"
    } catch {
        Write-Log "Failed to create backup folder: $_" "ERROR"
        exit 1
    }
}

function Export-ModernConfig {
    try {
        if (Get-Command Export-ADSyncServerConfiguration -ErrorAction SilentlyContinue) {
            $file = Join-Path $BackupFolder "FullExport.json"
            Export-ADSyncServerConfiguration -Path $file -ErrorAction Stop
            Write-Log "Modern export completed."
            return $true
        } else {
            Write-Log "Modern export cmdlet not available. Using fallback." "WARN"
            return $false
        }
    } catch {
        Write-Log "Modern export failed: $_" "ERROR"
        return $false
    }
}

function Export-FallbackConfig {
    try {
        Write-Log "Starting fallback data collection..."

        Get-ADSyncConnector | ConvertTo-Json -Depth 5 | Out-File "$BackupFolder\Connectors.json"
        Get-ADSyncRule | ConvertTo-Json -Depth 5 | Out-File "$BackupFolder\SyncRules.json"
        Get-ADSyncScheduler | ConvertTo-Json -Depth 5 | Out-File "$BackupFolder\Scheduler.json"
        Get-ADSyncGlobalSettings | ConvertTo-Json -Depth 5 | Out-File "$BackupFolder\GlobalSettings.json"

        Get-ADSyncConnector | ForEach-Object {
            $name = $_.Name -replace '[\\/:*?"<>|]', '_'
            Get-ADSyncConnectorRunProfile -ConnectorName $_.Name |
                ConvertTo-Json -Depth 5 |
                Out-File "$BackupFolder\RunProfile_$name.json"
        }

        Write-Log "Fallback export completed."
    } catch {
        Write-Log "Fallback export failed: $_" "ERROR"
        exit 4
    }
}

function Backup-Registry {
    try {
        reg export "HKLM\SOFTWARE\Microsoft\Azure AD Connect" "$BackupFolder\Registry.reg" /y | Out-Null
        Write-Log "Registry exported."
    } catch {
        Write-Log "Registry export failed: $_" "ERROR"
    }
}

function Get-SystemInfo {
    try {
        $file = "$BackupFolder\SystemInfo.txt"
        $module = Get-Module -ListAvailable ADSync | Select Name,Version

        @(
            "Computer: $ComputerName"
            "Date: $(Get-Date)"
            "`nADSync Module:"
            ($module | Out-String)
        ) | Out-File $file

        Write-Log "System info collected."
    } catch {
        Write-Log "System info collection failed: $_" "ERROR"
    }
}

function Compress-Backup {
    try {
        if (Test-Path $ZipFile) { Remove-Item $ZipFile -Force }
        Compress-Archive -Path "$BackupFolder\*" -DestinationPath $ZipFile -Force
        Write-Log "Backup compressed: $ZipFile"
    } catch {
        Write-Log "Compression failed: $_" "ERROR"
    }
}
#endregion

#region Main
try {
    Write-Log "===== START ====="

    Test-ADSyncModule
    Ensure-Service
    New-BackupFolder

    $modernSuccess = Export-ModernConfig
    if (-not $modernSuccess) {
        Export-FallbackConfig
    }

    Backup-Registry
    Get-SystemInfo
    Compress-Backup

    Write-Log "===== SUCCESS ====="
    exit 0
}
catch {
    Write-Log "Unhandled error: $_" "ERROR"
    exit 1
}
finally {
    Write-Log "===== END ====="
}
#endregion