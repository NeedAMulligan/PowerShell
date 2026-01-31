# You need to have installed the Dell Warranty Command Program before running this script #

# EXIT CODES
# 0    = Success
# 1001 = Input CSV missing
# 1002 = Dell Warranty CLI tool not found
# 1003 = Log directory/Path creation failed
# 1004 = CLI execution failed or no output generated

$ExitCode = 0
$ErrorActionPreference = "Stop"

# ==============================================================================
# VARIABLES CONFIGURATION
# ==============================================================================
$WorkingDir      = "C:\temp"
$InputFileName   = "DellSerialNumbers.csv"
$OutputFileName  = "DellWarranty_Final_Report.csv"

# Construct Full Paths
$InputFilePath   = Join-Path $WorkingDir $InputFileName
$FinalExportPath = Join-Path $WorkingDir $OutputFileName
$TempRawExport   = Join-Path $WorkingDir "DellRawExport_Temp.csv"

# Logging Setup
$ScriptName      = "DellWarranty_Portable"
$Timestamp       = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile         = Join-Path $WorkingDir "$($ScriptName)_$($Timestamp).log"
# ==============================================================================

# Ensure Working Directory Exists
if (-not (Test-Path $WorkingDir)) {
    try { 
        New-Item -Path $WorkingDir -ItemType Directory -Force | Out-Null 
    } catch { 
        exit 1003 
    }
}

function Write-Log {
    param([string]$Message)
    $Entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
    $Entry | Out-File -FilePath $LogFile -Append
}

Write-Log "Starting Portable Batch Process."
Write-Log "Input File: $InputFilePath"
Write-Log "Target Export: $FinalExportPath"

# 1. Prerequisite Check: Input File
if (-not (Test-Path $InputFilePath)) {
    Write-Log "ERROR: Input file $InputFilePath not found. Ensure the CSV is staged correctly."
    exit 1001
}

# 2. Dynamic Discovery of Dell CLI Tool
$SearchPaths = @("${env:ProgramFiles}\Dell", "${env:ProgramFiles(x86)}\Dell")
$DellCliPath = $null

foreach ($Path in $SearchPaths) {
    if (Test-Path $Path) {
        $Found = Get-ChildItem -Path $Path -Filter "DellWarranty-CLI.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($Found) { 
            $DellCliPath = $Found.FullName
            break 
        }
    }
}

if (-not $DellCliPath) {
    Write-Log "ERROR: Dell CLI Tool (DellWarranty-CLI.exe) not found in Program Files."
    exit 1002
}

Write-Log "Tool located at: $DellCliPath"

# 3. Execute Native Batch
Write-Log "Running Dell CLI Batch Mode..."
try {
    # Execute with /I (Input) and /E (Export)
    # /V (Verbose) helps populate our log file if redirected
    $Process = Start-Process -FilePath $DellCliPath -ArgumentList "/I=$InputFilePath", "/E=$TempRawExport", "/V" -Wait -NoNewWindow -PassThru
    
    if (Test-Path $TempRawExport) {
        Write-Log "Native batch export generated successfully."
        
        # 4. Finalize and Cleanup
        # Overwrite the final export path with the new data
        Move-Item -Path $TempRawExport -Destination $FinalExportPath -Force
        Write-Log "Process Complete. Final data moved to: $FinalExportPath"
    } else {
        Write-Log "ERROR: Dell tool exited with code $($Process.ExitCode) but no export file was found."
        $ExitCode = 1004
    }
} catch {
    Write-Log "Critical Exception: $($_.Exception.Message)"
    $ExitCode = 1
}

exit $ExitCode
