<#
.SYNOPSIS
    Parses Exclusions JSON into a readable CSV for Excel.
    
.DESCRIPTION
    0    = Success
    1001 = JSON file not found
    1002 = JSON file is empty or invalid
    1003 = Failed to create log or output directory
#>

$ExitCode = 0
$ErrorActionPreference = "Stop"

# Define Paths
$JsonPath = "path\to\your\file.json" # Update this path
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogDir = "C:\temp"
$LogFile = Join-Path $LogDir "ParseExclusions_$($Timestamp).log"
$OutputFile = Join-Path $LogDir "Exclusions_Report_$($Timestamp).csv"

# Function to log activity
function Write-Log {
    param([string]$Message)
    $LogMsg = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
    Add-Content -Path $LogFile -Value $LogMsg
}

try {
    # Ensure log directory exists
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir | Out-Null
    }

    Write-Log "Starting JSON parsing process."

    if (-not (Test-Path $JsonPath)) {
        Write-Log "ERROR: JSON file not found at $JsonPath"
        exit 1001
    }

    # Load and Parse JSON
    $RawData = Get-Content -Raw -Path $JsonPath | ConvertFrom-Json
    
    if (-not $RawData.exclusions) {
        Write-Log "ERROR: No exclusion data found in JSON."
        exit 1002
    }

    Write-Log "Processing $($RawData.exclusions.Count) exclusion entries."

    # Flatten and Select Relevant Fields
    $ParsedData = $RawData.exclusions | Select-Object `
        @{Name="Application"; Expression={$_.description}},
        @{Name="Condition/Path"; Expression={$_.condition}},
        @{Name="Category"; Expression={$_.category}},
        @{Name="Type"; Expression={$_.type}},
        @{Name="OS"; Expression={$_.os}},
        @{Name="Scope"; Expression={$_.scopePath}},
        @{Name="CreatedDate"; Expression={$_.created}},
        @{Name="LastUpdate"; Expression={$_.lastUpdate}}

    # Export to CSV
    $ParsedData | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding utf8
    
    Write-Log "Success: Data exported to $OutputFile"
    $ExitCode = 0

} catch {
    Write-Log "FATAL ERROR: $($_.Exception.Message)"
    $ExitCode = 1
}

exit $ExitCode
