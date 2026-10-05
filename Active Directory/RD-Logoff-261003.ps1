#requires -Version 5.1

<#
.SYNOPSIS
    Clears temporary files from specified application directories.

.DESCRIPTION
    Checks specified application temporary directories for accumulated files, removes them safely, 
    writes execution logs to C:\Temp, and automatically performs 7-day log cleanup maintenance. 
    Supports native -WhatIf and -Confirm safety parameters.

.PARAMETER SourcePaths
    An array of target folder paths to inspect and clear. Defaults to Brewpoint and Auto-Shopkeeper temp paths.

.PARAMETER LogDirectory
    The local directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Clear-ApplicationTemp.ps1 -WhatIf

.EXAMPLE
    .\Clear-ApplicationTemp.ps1 -SourcePaths "$env:appdata\CustomApp\Temp"

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: User profile read/write permissions on target temp folders.
    Change Log   :
        1.0 - Initial sanitized production release.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false, Position = 0, HelpMessage = "Specify array of target temporary folders to clear.")]
    [string[]]$SourcePaths = @(
        "$env:appdata\Brewpoint\Temp",
        "$env:Appdata\Auto-Shopkeeper\Temp"
    ),

    [Parameter(Mandatory = $false, HelpMessage = "Specify directory for execution log storage.")]
    [ValidateNotNullOrEmpty()]
    [string]$LogDirectory = "C:\Temp"
)

# --------------------------------------------------------------------------
# 1. PREREQUISITES & PRIVILEGE CHECKS
# --------------------------------------------------------------------------
# No administrative elevation strictly required for user AppData paths.

# --------------------------------------------------------------------------
# 2. LOGGING INITIALIZATION & HOUSEKEEPING
# --------------------------------------------------------------------------
$ScriptName = "Clear_ApplicationTempFolders"
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
    Write-Log "Initializing temporary folder cleanup routine..." "INFO"

    $ClearedCount = 0

    foreach ($TargetDir in $SourcePaths) {
        if (-not (Test-Path -Path $TargetDir)) {
            Write-Log "Target path does not exist or is not accessible: $TargetDir" "WARN"
            continue
        }

        $Items = Get-ChildItem -Path $TargetDir -Force -ErrorAction SilentlyContinue

        if (-not $Items -or $Items.Count -eq 0) {
            Write-Log "Folder is already empty: $TargetDir" "INFO"
            continue
        }

        Write-Log "Found $($Items.Count) item(s) in '$TargetDir'. Preparing cleanup..." "INFO"

        if ($PSCmdlet.ShouldProcess("$TargetDir", "Remove all contents within temporary directory")) {
            try {
                Remove-Item -Path "$TargetDir\*" -Force -Recurse -ErrorAction Stop
                Write-Log "SUCCESS: Cleared contents of '$TargetDir'." "INFO"
                $ClearedCount++
            }
            catch {
                Write-Log "ERROR clearing path '$TargetDir': $($_.Exception.Message)" "ERROR"
            }
        }
    }

    Write-Log "Temporary folder cleanup routine complete. Successfully cleared $ClearedCount target folder(s)." "INFO"
}
catch {
    Write-Log "CRITICAL ERROR during temporary folder cleanup execution: $($_.Exception.Message)" "ERROR"
    exit 1
}