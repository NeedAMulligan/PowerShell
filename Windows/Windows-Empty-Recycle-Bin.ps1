<#
.SYNOPSIS
    Completely empties the Recycle Bin for all users on all drives.
    
.EXITCODES
    0    = Success
    1001 = Script encountered an error during execution
    1002 = Directory creation failed
#>

$ErrorActionPreference = "Stop"
$ExitCode = 0

# Define Log Path and Filename
$LogDir = "C:\temp"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile = Join-Path -Path $LogDir -ChildPath "EmptyRecycleBin_$($Timestamp).log"

# Function for Logging
function Write-Log {
    param([string]$Message)
    $Entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
    Add-Content -Path $LogFile -Value $Entry
}

try {
    # 1. Ensure Log Directory exists
    if (-not (Test-Path -Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
    
    Write-Log "Starting Recycle Bin cleanup process."

    # 2. Identify all fixed drives
    $Drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.DisplayRoot -match ':' -or $_.Name -match '^[A-Z]$'}
    
    foreach ($Drive in $Drives) {
        $DriveLetter = "$($Drive.Name):"
        Write-Log "Processing drive: $DriveLetter"
        
        try {
            # 3. Clear the Recycle Bin
            # -Force removes the "Are you sure?" prompt
            # -ErrorAction Continue allows the script to proceed even if one drive fails
            Clear-RecycleBin -DriveLetter $DriveLetter -Force -ErrorAction SilentlyContinue
            Write-Log "Successfully cleared Recycle Bin on $DriveLetter"
        }
        catch {
            Write-Log "Non-terminating error on $DriveLetter : $($_.Exception.Message)"
        }
    }

    Write-Log "Cleanup complete."
}
catch {
    $ExitCode = 1001
    if (Test-Path -Path $LogFile) {
        Write-Log "CRITICAL ERROR: $($_.Exception.Message)"
    }
}
finally {
    exit $ExitCode
}
