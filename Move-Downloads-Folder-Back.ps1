# Exit Code Explanations:
# 0: Success - The Downloads folder path was successfully restored to %USERPROFILE%\Downloads and files were moved/verified.
# 1: Error - Failed to create the log file, or a critical step in the folder/registry modification failed.

# --- Configuration ---
$LogFilePath = "C:\temp\MoveDownloadsToLocal_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$NewDownloadsPath = [Environment]::ExpandEnvironmentVariables("%USERPROFILE%\Downloads")
$RegistryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
# Registry value names for Downloads folder path
$KnownFolderGUID1 = "{374DE290-123F-4565-9164-39C4925E467B}" # Newer GUID for Downloads
$KnownFolderGUID2 = "{7D83EE9B-2244-4E70-B1F5-5393042AF1E4}" # Older GUID for Downloads

# --- Functions ---

function Write-Log {
    param([string]$Message, [string]$Type = "INFO")
    try {
        $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "$TimeStamp [$Type] $Message" | Out-File -FilePath $LogFilePath -Encoding UTF8 -Append
    } catch {
        # If logging fails, just write to console (which is now allowed)
        Write-Host "FATAL LOGGING ERROR: $_" -ForegroundColor Red
    }
}

# --- Main Script ---

Write-Host "🚀 Starting script to move Downloads folder from OneDrive back to local profile." -ForegroundColor Cyan
Write-Log "Script started to move Downloads folder back to local user profile."
Write-Log "Log file location: $LogFilePath"

# 1. Ensure the C:\temp directory exists for the log file
try {
    Write-Host "Checking for C:\temp directory..." -ForegroundColor Yellow
    if (-not (Test-Path "C:\temp")) {
        New-Item -Path "C:\temp" -ItemType Directory | Out-Null
        Write-Log "Created C:\temp directory."
        Write-Host "Created C:\temp directory." -ForegroundColor Green
    }
} catch {
    Write-Host "❌ ERROR: Failed to create C:\temp. Exiting with code 1." -ForegroundColor Red
    Write-Log "ERROR: Failed to create C:\temp. Exiting with code 1." "ERROR"
    exit 1
}

# 2. Get the current Downloads path from the registry for logging/moving
try {
    $CurrentDownloadsPath = Get-ItemPropertyValue -Path $RegistryPath -Name $KnownFolderGUID1 -ErrorAction Stop
    Write-Host "Current Downloads path detected: $CurrentDownloadsPath" -ForegroundColor DarkYellow
    Write-Log "Current Downloads path (from registry): $CurrentDownloadsPath"
} catch {
    Write-Host "⚠️ WARNING: Could not read current Downloads path from registry. Assuming OneDrive path." -ForegroundColor Yellow
    Write-Log "WARNING: Could not read current Downloads path from registry. Assuming default path." "WARNING"
    $CurrentDownloadsPath = $null
}

# 3. Create the new local Downloads folder if it doesn't exist
try {
    Write-Host "Checking for desired local Downloads path: $NewDownloadsPath" -ForegroundColor Yellow
    if (-not (Test-Path $NewDownloadsPath)) {
        New-Item -Path $NewDownloadsPath -ItemType Directory | Out-Null
        Write-Log "Created local default Downloads folder: $NewDownloadsPath"
        Write-Host "Created new local Downloads folder." -ForegroundColor Green
    }
} catch {
    Write-Host "❌ ERROR: Failed to create the new local Downloads folder. Exiting with code 1." -ForegroundColor Red
    Write-Log "ERROR: Failed to create the new local Downloads folder at $NewDownloadsPath. Exiting with code 1." "ERROR"
    exit 1
}

# 4. Move files from the old location (OneDrive) to the new location (if the path is different)
if ($CurrentDownloadsPath -ne $NewDownloadsPath -and (Test-Path $CurrentDownloadsPath)) {
    Write-Host "📦 Moving contents from old Downloads location to the new local folder..." -ForegroundColor Yellow
    try {
        # Move all contents (*) recursively
        Move-Item -Path (Join-Path $CurrentDownloadsPath "*") -Destination $NewDownloadsPath -Force -Recurse -ErrorAction Stop
        Write-Log "Successfully moved files from $CurrentDownloadsPath to $NewDownloadsPath."
        Write-Host "✅ File move complete." -ForegroundColor Green
    } catch {
        Write-Host "⚠️ WARNING: Failed to move some or all files. Files may need to be moved manually. Error: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Log "WARNING: Failed to move some or all files. Files may need to be moved manually. Error: $($_.Exception.Message)" "WARNING"
    }
} else {
    Write-Host "Files are already at the correct path or old path not found. Skipping file move." -ForegroundColor Cyan
    Write-Log "File move skipped: Paths are the same or the old path does not exist."
}

# 5. Update the registry keys to point to the new local path
try {
    Write-Host "📝 Updating Windows Registry to set new default path..." -ForegroundColor Yellow
    Set-ItemProperty -Path $RegistryPath -Name $KnownFolderGUID1 -Value $NewDownloadsPath -Force -Type String -ErrorAction Stop
    Set-ItemProperty -Path $RegistryPath -Name $KnownFolderGUID2 -Value $NewDownloadsPath -Force -Type String -ErrorAction Stop
    
    Write-Log "Registry keys updated successfully."
    Write-Host "✅ Registry updated. The new default Downloads path is set to: $NewDownloadsPath" -ForegroundColor Green
    Write-Host "A REBOOT IS RECOMMENDED for changes to take full effect." -ForegroundColor Magenta
    Write-Log "Script finished with exit code 0."
    exit 0
} catch {
    Write-Host "❌ ERROR: Failed to update registry. Exiting with code 1. Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Log "ERROR: Failed to update registry. Exiting with code 1. Error: $($_.Exception.Message)" "ERROR"
    exit 1
}