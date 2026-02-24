<#
.SYNOPSIS
    Silent RMM Export of Microsoft Entra Connect configuration.
.DESCRIPTION
    Optimized for background execution. Outputs a timestamped folder to C:\temp 
    containing the official XML backup and a lean JSON file.
.EXITCODES
    0 = Success
    1 = General Error
    2 = Insufficient Privileges
    3 = ADSync Module Not Found
#>

# ---------------------------------------------------------------------------
# VARIABLES (Centralized for easy RMM adjustment)
# ---------------------------------------------------------------------------
$Hostname  = $env:COMPUTERNAME
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

$Config = @{
    BaseDir         = "C:\temp\ADSyncBackup_${Hostname}_${Timestamp}"
    JsonFileName    = "ADSyncConfig_${Hostname}.json"
    RequiredModule  = "ADSync"
}

# ---------------------------------------------------------------------------
# LOGGING FUNCTION (Silent)
# ---------------------------------------------------------------------------
if (!(Test-Path $Config.BaseDir)) {
    New-Item -Path $Config.BaseDir -ItemType Directory -Force | Out-Null
}

$LogPath = Join-Path $Config.BaseDir "Backup_Process_${Hostname}.log"

Function Write-Log {
    Param ([string]$Message, $Level = "INFO")
    $Stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$Stamp] [$Level] - $Message" | Out-File -FilePath $LogPath -Append
}

# ---------------------------------------------------------------------------
# MAIN EXECUTION
# ---------------------------------------------------------------------------
Try {
    Write-Log "Starting Silent Export on ${Hostname}"

    # 1. Validation Logic
    if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Log "CRITICAL: Run as Administrator required." "ERROR"
        exit 2
    }

    if (-not (Get-Module -ListAvailable -Name $Config.RequiredModule)) {
        Write-Log "CRITICAL: ADSync module not found." "ERROR"
        exit 3
    }
    
    Import-Module $Config.RequiredModule -ErrorAction Stop

    # 2. Official XML Backup (For Wizard Restore)
    Write-Log "Generating Official XML Export..."
    $XmlFolder = Join-Path $Config.BaseDir "Wizard_Import_Files"
    New-Item -Path $XmlFolder -ItemType Directory -Force | Out-Null
    
    # Executing the core backup
    Get-ADSyncServerConfiguration -Path $XmlFolder | Out-Null

    # 3. Lean JSON Backup (For Documentation)
    Write-Log "Generating Lean JSON file..."
    $Connectors = Get-ADSyncConnector | Select-Object Name, Type, @{Name='Rules'; Expression={$_.AttributeMappings}}
    $SyncRules = Get-ADSyncRule | Select-Object Name, Direction, Precedence, AttributeMappings
    
    $SyncData = @{
        Metadata = @{
            ExportDate   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            SourceServer = $Hostname
        }
        Connectors = $Connectors
        Rules      = $SyncRules
    }

    $JsonFullPath = Join-Path $Config.BaseDir $Config.JsonFileName
    $SyncData | ConvertTo-Json -Depth 6 | Out-File -FilePath $JsonFullPath -Encoding UTF8 -Force

    Write-Log "Export Complete. Files located at $($Config.BaseDir)"
    
    # Outputting the path so the RMM can capture it in the 'Success' result
    Write-Output "SUCCESS: Backup saved to $($Config.BaseDir)"
    exit 0
}
Catch {
    $ErrorMessage = $_.Exception.Message
    Write-Log "FATAL ERROR: $ErrorMessage" "ERROR"
    # Ensure the RMM sees the failure
    Write-Error "ADSync Backup Failed: $ErrorMessage"
    exit 1
}