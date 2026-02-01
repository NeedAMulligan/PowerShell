# EXIT CODES
# 0    = Success
# 1001 = Input CSV missing
# 1002 = Dell Warranty CLI tool not found
# 1003 = Log directory creation failed
# 1004 = CLI execution failed or no output generated

$ExitCode = 0
$ErrorActionPreference = "Stop"

# Setup Logging & Paths
$ScriptName = "DellWarranty_CleanBatch"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogDir = "C:\temp"
$LogFile = Join-Path $LogDir "$($ScriptName)_$($Timestamp).log"
$InputFile = "C:\temp\DellWarranty.csv"
$FinalOutputFile = "C:\temp\DellWarranty_Final_$($Timestamp).csv"

# Ensure Log Directory Exists
if (-not (Test-Path $LogDir)) {
    try { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null } catch { exit 1003 }
}

function Write-Log {
    param([string]$Message)
    $Entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
    $Entry | Out-File -FilePath $LogFile -Append
}

Write-Log "Starting Cleaned Native Batch Process."

# 1. Locate Tool
$SearchPaths = @("${env:ProgramFiles}\Dell", "${env:ProgramFiles(x86)}\Dell")
$DellCliPath = $null
foreach ($Path in $SearchPaths) {
    if (Test-Path $Path) {
        $Found = Get-ChildItem -Path $Path -Filter "DellWarranty-CLI.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($Found) { $DellCliPath = $Found.FullName; break }
    }
}

if (-not $DellCliPath) {
    Write-Log "ERROR: Dell CLI Tool not found."
    exit 1002
}

# 2. Execute Native Batch
# We point the tool to a specific temp filename so we can find it easily for cleanup
$TempExportPath = "C:\temp\DellRawExport.csv"

Write-Log "Executing Dell Native Batch..."
try {
    # Using the tool's native /I and /E switches
    $Process = Start-Process -FilePath $DellCliPath -ArgumentList "/I=$InputFile", "/E=$TempExportPath", "/V" -Wait -NoNewWindow -PassThru
    
    if (Test-Path $TempExportPath) {
        Write-Log "Native export successful. Proceeding to cleanup."
        
        # 3. Move/Rename the file to the Final Output name
        Move-Item -Path $TempExportPath -Destination $FinalOutputFile -Force
        Write-Log "Final CSV ready: $FinalOutputFile"
        
        # 4. Cleanup Artifacts
        # The Dell tool sometimes leaves log files or empty folders in ProgramData or the local temp
        $Artifacts = @("C:\temp\DellRawExport.csv") # Safety check
        foreach ($File in $Artifacts) {
            if (Test-Path $File) { Remove-Item $File -Force }
        }
    } else {
        Write-Log "ERROR: Dell tool finished but $TempExportPath was not created."
        $ExitCode = 1004
    }
} catch {
    Write-Log "Critical error during execution: $($_.Exception.Message)"
    $ExitCode = 1
}

Write-Log "Process complete. Exit Code: $ExitCode"
exit $ExitCode