#requires -Version 5.1

<#
.SYNOPSIS
    Deploys and synchronizes application runtime files and temporary directories for local user profiles.

.DESCRIPTION
    Ensures local application directories and temporary folders exist under the user's AppData path, 
    cleans legacy runtime files, and copies fresh application runtimes from a designated source path. 
    Includes native -WhatIf/-Confirm safety controls, execution logging in C:\Temp, and automated 7-day log maintenance cleanup.

.PARAMETER AppConfigs
    A Hashtable mapping target AppData subdirectories to their respective source runtime paths and file names.

.PARAMETER LogDirectory
    The local directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Deploy-ApplicationRuntimes.ps1 -WhatIf

.EXAMPLE
    .\Deploy-ApplicationRuntimes.ps1 -Confirm:$false

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: User profile read/write permissions on AppData and source network/local shares.
    Change Log   :
        1.0 - Initial sanitized production release.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Specify application deployment configurations mapping destination AppData paths to source runtimes.")]
    [hashtable]$AppConfigs = @{
        "Brewpoint" = @{
            BasePath   = "$env:Appdata\Brewpoint"
            SourcePath = "$env:SystemDrive\Brewpoint"
            FileName   = "BrewpointApp.accdr"
        }
        "Auto-Shopkeeper" = @{
            BasePath   = "$env:Appdata\Auto-Shopkeeper"
            SourcePath = "$env:SystemDrive\Auto-ShopKeeper"
            FileName   = "Auto-ShopKeeper.accdr"
        }
    },

    [Parameter(Mandatory = $false, HelpMessage = "Specify directory for execution log storage.")]
    [ValidateNotNullOrEmpty()]
    [string]$LogDirectory = "C:\Temp"
)

# --------------------------------------------------------------------------
# 1. PREREQUISITES & PRIVILEGE CHECKS
# --------------------------------------------------------------------------
# User profile AppData operations do not strictly require administrative elevation.

# --------------------------------------------------------------------------
# 2. LOGGING INITIALIZATION & HOUSEKEEPING
# --------------------------------------------------------------------------
$ScriptName = "Deploy_ApplicationRuntimes"
$DateStamp  = Get-Date -Format "yyyyMMdd_HHmmss"

if (-not (Test-Path -Path $LogDirectory)) {
    New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
}

# Log rotation: Remove log files older than 7 days from C:\Temp
Get-ChildItem -Path $LogDirectory -Filter "*.log" -File -ErrorAction SilentlyContinue | 
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } | 
    Remove-Item -Force -ErrorAction SilentlyContinue

$LogFile = Join-Path -Path $LogDirectory -ChildPath "$($ScriptName)_$($DateStamp).log"

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )
    $LogEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] - $Message"
    $LogEntry | Out-File -FilePath $LogFile -Append -Encoding utf8
    
    $Color = switch ($Level) {
        "ERROR" { "Red" }
        "WARN"  { "Yellow" }
        Default { "Cyan" }
    }
    Write-Host $LogEntry -ForegroundColor $Color
}

# --------------------------------------------------------------------------
# 3. SCRIPT EXECUTION
# --------------------------------------------------------------------------
try {
    Write-Log "Initializing Application Runtime Deployment routine..." "INFO"

    if (-not $AppConfigs -or $AppConfigs.Count -eq 0) {
        Write-Log "No application configurations provided." "WARN"
        return
    }

    $SuccessCount = 0
    $FailureCount = 0

    foreach ($AppName in $AppConfigs.Keys) {
        $Config     = $AppConfigs[$AppName]
        $BasePath   = $Config.BasePath
        $SourcePath = $Config.SourcePath
        $FileName   = $Config.FileName
        $TempPath   = Join-Path -Path $BasePath -ChildPath "Temp"

        Write-Log "Processing application deployment for: $AppName" "INFO"

        try {
            # 1. Ensure Base AppData Directory Exists
            if (-not (Test-Path -Path $BasePath)) {
                if ($PSCmdlet.ShouldProcess($BasePath, "Create application base directory")) {
                    New-Item -ItemType Directory -Force -Path $BasePath -ErrorAction Stop | Out-Null
                    Write-Log "Created base directory: $BasePath" "INFO"
                }
            }

            # 2. Clean up existing files in base folder (excluding subdirectories like Temp)
            if (Test-Path -Path $BasePath) {
                $ExistingFiles = Get-ChildItem -Path $BasePath -File -ErrorAction SilentlyContinue
                if ($ExistingFiles) {
                    if ($PSCmdlet.ShouldProcess($BasePath, "Remove existing runtime files")) {
                        Remove-Item -Path "$BasePath\*.*" -Force -ErrorAction Stop
                        Write-Log "Cleaned existing files from '$BasePath'." "INFO"
                    }
                }
            }

            # 3. Ensure Temp Directory Exists
            if (-not (Test-Path -Path $TempPath)) {
                if ($PSCmdlet.ShouldProcess($TempPath, "Create application temporary directory")) {
                    New-Item -ItemType Directory -Force -Path $TempPath -ErrorAction Stop | Out-Null
                    Write-Log "Created temporary directory: $TempPath" "INFO"
                }
            }

            # 4. Copy Runtime File from Source
            $SourceFile = Join-Path -Path $SourcePath -ChildPath $FileName
            if (Test-Path -Path $SourceFile) {
                if ($PSCmdlet.ShouldProcess("$SourceFile", "Copy runtime file to '$BasePath'")) {
                    Copy-Item -Path $SourceFile -Destination $BasePath -Recurse -Force -ErrorAction Stop
                    Write-Log "SUCCESS: Copied '$FileName' from '$SourcePath' to '$BasePath'." "INFO"
                    $SuccessCount++
                }
            }
            else {
                Write-Log "WARNING: Source runtime file not found at path: $SourceFile" "WARN"
                $FailureCount++
            }
        }
        catch {
            Write-Log "ERROR deploying application '$AppName': $($_.Exception.Message)" "ERROR"
            $FailureCount++
        }
    }

    Write-Log "Application Runtime Deployment routine complete. Successful: $SuccessCount | Failed: $FailureCount" "INFO"
}
catch {
    Write-Log "CRITICAL ERROR during application deployment execution: $($_.Exception.Message)" "ERROR"
    exit 1
}