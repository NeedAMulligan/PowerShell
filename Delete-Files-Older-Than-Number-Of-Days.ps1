<#
.SYNOPSIS
  Deletes files in a specified directory that are older than a set number of days.

.DESCRIPTION
  This script finds all files in the target directory and its subdirectories
  that have a LastWriteTime property older than the specified age limit (in days).
  It runs silently and logs all actions and errors to a file in the configured LogDir.

.NOTES
  Author: Gemini
  Date: September 4, 2025 (Updated: 2025-09-26)
  Version: 2.1 (Updated Log Path)
  Exit Codes:
    0: Script completed successfully and files were processed (even if no files were deleted).
    1: Script failed due to an exception (e.g., path not found, permission error).

.EXAMPLE
  To run this script, simply execute it from PowerShell:
  PS C:\> .\FileCleanup.ps1

  By default, it uses the -WhatIf parameter for safety, which shows what
  would be deleted without actually deleting anything. Remove -WhatIf
  to perform the actual deletion.
#>

# ==============================================================================
# SCRIPT CONFIGURATION
# Modify these variables to fit your needs.
# ==============================================================================

# Specify the directory path where files should be deleted.
# IMPORTANT: Be very careful with this path. Ensure it is correct.
# Note: This script only targets FILES for deletion, not directories.
$TargetDirectory = "F:\"

# Set the age limit in days. Any files older than this will be deleted.
# Change 'NUMBER-OF-DAYS' to your desired number of days (e.g., 30 for one month).
$AgeInDays = 45

# ==============================================================================
# LOGGING SETUP
# ==============================================================================

# Set the directory for storing log files. Logs will now be stored in F:\logs.
$LogDir = "F:\logs"
# Create a dynamically named log file path
$LogPath = Join-Path -Path $LogDir -ChildPath "FileCleanup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Function to write messages to the log file
function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [Parameter(Mandatory=$false)][string]$Level = "INFO"
    )
    # Ensure the log directory exists before logging
    if (-not (Test-Path -Path $LogDir -PathType Container)) {
        try {
            New-Item -Path $LogDir -ItemType Directory | Out-Null
        } catch {
            # If we can't create the log directory, log to the console (as a last resort) and exit
            Write-Host "FATAL: Could not create log directory '$LogDir'. Script aborted."
            exit 1
        }
    }
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] [$Level] $Message"
    $LogEntry | Out-File -FilePath $LogPath -Append -Encoding UTF8
}

# ==============================================================================
# SCRIPT LOGIC
# ==============================================================================

Write-Log "Starting file deletion script."
Write-Log "Target Directory: '$TargetDirectory'"
Write-Log "Age Limit: $AgeInDays days"

try {
    # Calculate the cutoff date. Any file with a LastWriteTime before this date will be deleted.
    $CutoffDate = (Get-Date).AddDays(-$AgeInDays)

    Write-Log "Cutoff date for deletion (based on LastWriteTime) is: $CutoffDate"

    # Input validation: Check if the target directory exists
    if (-not (Test-Path -Path $TargetDirectory -PathType Container)) {
        Write-Log "ERROR: Target directory not found or is inaccessible: '$TargetDirectory'" "ERROR"
        exit 1
    }

    # Find all files recursively in the target directory that are older than the cutoff date.
    # The -File parameter ensures that directories (like F:\logs) are skipped.
    $FilesToDelete = Get-ChildItem -Path $TargetDirectory -File -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $CutoffDate }

    if ($FilesToDelete -eq $null -or $FilesToDelete.Count -eq 0) {
        Write-Log "No files found to delete."
    } else {
        Write-Log "$($FilesToDelete.Count) files found that are older than the cutoff date."
        Write-Log "--- Starting Deletion Process (using -WhatIf for safety) ---"

        # The -WhatIf parameter is intentionally included here for safety, preventing actual deletion.
        # To perform the actual deletion, REMOVE "-WhatIf" from the Remove-Item command below.
        $FilesToDelete | ForEach-Object {
            $FileFullPath = $_.FullName
            try {
                # Add -WhatIf to test run, remove it to perform live deletion
                Remove-Item -Path $FileFullPath -Force -WhatIf
                Write-Log "PROCESSED: $FileFullPath (Action: REMOVED)"
            }
            catch {
                Write-Log "FAILED to delete file '$FileFullPath'. Error: $($_.Exception.Message)" "ERROR"
            }
        }

        Write-Log "--- Deletion Process Complete ---"
        Write-Log "NOTE: Actual deletion only occurs when '-WhatIf' is removed from the Remove-Item command."
    }

    Write-Log "Script finished successfully. (Exit Code 0)"
    exit 0

} catch {
    # Catch and log any unexpected errors that occur during the main script execution block.
    Write-Log "An UNEXPECTED error occurred during script execution." "FATAL"
    Write-Log "Error Details: $($_.Exception.Message)" "FATAL"
    exit 1
}