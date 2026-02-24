<#
.SYNOPSIS
    Exports Microsoft Entra Connect configuration in both XML and JSON formats.
.DESCRIPTION
    Creates a timestamped folder containing:
    1. A subfolder with the official XML files required for the Import Wizard.
    2. A single lean JSON file for human review and documentation.
.PARAMETER ExportPath
    The root directory for backups. Defaults to C:\temp.
#>

# ---------------------------------------------------------------------------
# VARIABLES
# ---------------------------------------------------------------------------
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Config = @{
    # This creates a unique folder for every run to prevent overwriting
    BaseDir         = "C:\temp\ADSyncFullBackup_$Timestamp"
    JsonFileName    = "ADSync_Documentation_Lean.json"
    RequiredModule  = "ADSync"
    ServiceName     = "ADSync"
}

# ---------------------------------------------------------------------------
# EXIT CODES: 0=Success, 1=General Error, 2=Not Admin, 3=Module Missing
# ---------------------------------------------------------------------------

# Ensure the base directory exists
if (!(Test-Path $Config.BaseDir)) {
    New-Item -Path $Config.BaseDir -ItemType Directory -Force | Out-Null
}

$LogPath = Join-Path $Config.BaseDir "Backup_Process.log"

Function Write-Log {
    Param (
        [Parameter(Mandatory=$true)]
        [string]$Message, 
        [ValidateSet("INFO", "WARN", "ERROR")] $Level = "INFO"
    )
    $Stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Stamp] [$Level] - $Message"
    $LogEntry | Out-File -FilePath $LogPath -Append

    $Color = "White"
    if ($Level -eq "ERROR") { $Color = "Red" }
    elseif ($Level -eq "WARN") { $Color = "Yellow" }
    Write-Host $LogEntry -ForegroundColor $Color
}

Function Start-UnifiedExport {
    Try {
        Write-Log "Starting Unified AD Sync Export..."

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

        # 2. Official XML Backup (Required for Disaster Recovery / Wizard Restore)
        Write-Log "Generating Official XML Export folder..."
        $XmlFolder = Join-Path $Config.BaseDir "Wizard_Import_Files"
        New-Item -Path $XmlFolder -ItemType Directory -Force | Out-Null
        
        # This command creates the exact structure the Microsoft Installer expects
        Get-ADSyncServerConfiguration -Path $XmlFolder

        # 3. Lean JSON Backup (For easy human reading/searching)
        Write-Log "Generating Lean JSON file (~700KB)..."
        $Connectors = Get-ADSyncConnector | Select-Object Name, Type, @{Name='Rules'; Expression={$_.AttributeMappings}}
        $SyncRules = Get-ADSyncRule | Select-Object Name, Direction, Precedence, AttributeMappings
        
        $SyncData = @{
            Metadata = @{
                ExportDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                SourceServer = $env:COMPUTERNAME
            }
            Connectors = $Connectors
            Rules = $SyncRules
        }

        $JsonFullPath = Join-Path $Config.BaseDir $Config.JsonFileName
        $SyncData | ConvertTo-Json -Depth 6 | Out-File -FilePath $JsonFullPath -Encoding UTF8 -Force

        # 4. Summary
        Write-Log "----------------------------------------------------"
        Write-Log "EXPORT COMPLETE"
        Write-Log "Location: $($Config.BaseDir)"
        Write-Log "DR Folder: \Wizard_Import_Files (Use this in the Entra Connect Installer)"
        Write-Log "Doc File:  $($Config.JsonFileName) (Use this for reading rules)"
        exit 0
    }
    Catch {
        Write-Log "FATAL ERROR: $($_.Exception.Message)" "ERROR"
        exit 1
    }
}

# Execute
Start-UnifiedExport
