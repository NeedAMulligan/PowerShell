# Exit Codes:
# 0 - Script executed successfully. The directory C:\Scripts either exists or was created.
# 1 - Script failed to create the directory C:\Scripts.

# --- Configuration ---
$TargetDirectory = "C:\Scripts"
$LogDirectory = "C:\temp"
$LogFilePath = "$LogDirectory\Create-ScriptsDir_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
# ---------------------

function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message
    )
    try {
        # Ensure the C:\temp directory exists first
        if (-not (Test-Path -Path $LogDirectory)) {
            New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
        }
        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "$Timestamp - $Message" | Out-File -FilePath $LogFilePath -Append -Encoding UTF8
    } catch {
        # Silent fail if logging fails
    }
}

Write-Log "--- Script Start ---"
Write-Log "Attempting to ensure directory exists: $TargetDirectory"

try {
    if (Test-Path -Path $TargetDirectory -PathType Container) {
        Write-Log "STATUS: Directory $TargetDirectory already exists. No action taken."
    } else {
        # Create the directory silently
        New-Item -Path $TargetDirectory -ItemType Directory -Force | Out-Null
        
        if (Test-Path -Path $TargetDirectory -PathType Container) {
            Write-Log "SUCCESS: Directory $TargetDirectory was created."
        } else {
            # This handles cases where New-Item didn't throw an error but creation still failed
            Write-Log "ERROR: Directory $TargetDirectory could not be verified after creation attempt. Check permissions."
            Write-Log "--- Script End ---"
            exit 1
        }
    }
    
    Write-Log "--- Script End ---"
    exit 0

} catch {
    Write-Log "FATAL ERROR: Failed to create or verify directory $TargetDirectory. $($_.Exception.Message)"
    Write-Log "--- Script End ---"
    exit 1
}