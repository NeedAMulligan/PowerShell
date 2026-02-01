# Exit Codes
# 0: Success - All requested programs were found and uninstallation was initiated.
# 1: Partial Success - One or more requested programs were NOT found, or one or more uninstall commands failed to execute.
# 2: Failure - An unexpected, critical error occurred during the script execution (e.g., severe permission issue).

$ExitCode = 0

# --- User-Defined Variables ---
$LogPath = "C:\Temp"
$LogFileName = "Remove_NAble_SolarWinds_Registry_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$LogFile = Join-Path -Path $LogPath -ChildPath $LogFileName

# List of target programs to uninstall (must match 'DisplayName' exactly as seen in Control Panel)
$ProgramsToUninstall = @(
    "Windows Agent",
    "File Cache Service Agent",
    "Patch Management Service Controller",
    "Request Handler Agent",
    "Ecosystem Agent"
)

# Registry paths to search for installed applications
$RegistryPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",        # 64-bit apps
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" # 32-bit apps
)
# --- End User-Defined Variables ---


# --- Function for Logging ---
Function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [Parameter(Mandatory=$false)][string]$Type = "INFO"
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] [$Type] :: $Message"
    Add-Content -Path $LogFile -Value $LogEntry -ErrorAction SilentlyContinue
}
# --- End Function for Logging ---


# Create the log directory if it doesn't exist
If (-not (Test-Path $LogPath)) {
    Write-Log -Message "Creating log directory: $LogPath"
    New-Item -Path $LogPath -ItemType Directory | Out-Null
}

Write-Log -Message "Script started. Log file: $LogFile"
Write-Log -Message "Target programs for removal: $($ProgramsToUninstall -join ', ')"

$ProgramsFoundCount = 0
$ProgramsToProcess = @()

# 1. Search the Registry for the Uninstall Strings
Write-Log -Message "Searching registry for program uninstall strings..."
ForEach ($ProgramName in $ProgramsToUninstall) {
    $App = Get-ItemProperty -Path $RegistryPaths -ErrorAction SilentlyContinue | Where-Object { 
        $_.DisplayName -eq $ProgramName 
    } | Select-Object -First 1

    If ($App) {
        $ProgramsFoundCount++
        $ProgramsToProcess += $App
        Write-Log -Message "Found '$($App.DisplayName)'. Uninstall String: '$($App.UninstallString)'"
    }
    Else {
        Write-Log -Message "Program '$ProgramName' NOT found in the uninstall registry keys." -Type "WARNING"
    }
}

# 2. Process and Execute the Uninstall Commands
If ($ProgramsToProcess.Count -gt 0) {
    Write-Log -Message "Found $($ProgramsToProcess.Count) application(s) to uninstall. Starting process..."

    ForEach ($App in $ProgramsToProcess) {
        $UninstallString = $App.UninstallString
        $DisplayName = $App.DisplayName
        
        # Determine the Executable and Arguments
        # Remove surrounding quotes from the string if present
        $CleanString = $UninstallString.Trim('"')
        
        # Check if the command starts with 'MsiExec.exe' or similar
        If ($CleanString -match 'MsiExec\.exe' -or $CleanString -match 'msiexec\.exe') {
            # Standard MSI uninstalls: replace /I (Install/Modify) with /X (Uninstall) and append /qn (Quiet No-UI)
            $Executable = 'msiexec.exe'
            # Look for the product code GUID, replace /I or /V with /X, and ensure /qn for quiet mode
            $Arguments = $CleanString -replace '/I','/X' -replace '/V','/X'
            # Append /qn (Quiet, No UI) if it's not already present
            if ($Arguments -notmatch '/qn' -and $Arguments -notmatch '/q' ) { $Arguments += " /qn" }
            
            Write-Log -Message "MSI Uninstall command for '$DisplayName': $Executable $Arguments"
        }
        # Check for standard uninstaller executables like 'unins000.exe'
        ElseIf ($CleanString -match 'unins000\.exe' -or $CleanString -match 'uninstall\.exe') {
            # Split the command into executable and arguments
            $Parts = $CleanString -split '\s+', 2
            $Executable = $Parts[0].Trim('"')
            $Arguments = $Parts[1]
            # Standard silent switch for Inno Setup (often used by these agents) is /SILENT or /VERYSILENT
            if ($Arguments -notmatch '/silent' -and $Arguments -notmatch '/verysilent') { $Arguments += " /SILENT" }
            
            Write-Log -Message "Custom Uninstaller command for '$DisplayName': $Executable $Arguments"
        }
        Else {
            # Fallback for non-MSI/non-standard uninstaller, try to execute with /s (silent)
            $Parts = $CleanString -split '\s+', 2
            $Executable = $Parts[0].Trim('"')
            $Arguments = $Parts[1] + " /s"
            
            Write-Log -Message "Generic command for '$DisplayName': $Executable $Arguments" -Type "WARNING"
        }

        # Execute the command
        Try {
            # Using -Wait ensures the script pauses until the uninstaller finishes (crucial for stability)
            Start-Process -FilePath $Executable -ArgumentList $Arguments -Wait -NoNewWindow -ErrorAction Stop | Out-Null
            Write-Log -Message "Successfully executed silent uninstall command for '$DisplayName'."
        }
        Catch {
            Write-Log -Message "Failed to execute uninstall command for '$DisplayName'. Error: $($_.Exception.Message)" -Type "ERROR"
            # Set exit code to 1 if a command fails
            if ($ExitCode -ne 2) {$ExitCode = 1} 
        }
    }
}
Else {
    Write-Log -Message "No programs were found from the list to process." -Type "WARNING"
    $ExitCode = 1
}

# 3. Final Exit Code Check
If ($ProgramsFoundCount -lt $ProgramsToUninstall.Count) {
    $MissingPrograms = $ProgramsToUninstall | Where-Object { $_ -notin $ProgramsToProcess.DisplayName }
    Write-Log -Message "The following requested programs were NOT found: $($MissingPrograms -join ', ')" -Type "WARNING"
    # If any were missing, set exit code to 1
    If ($ExitCode -ne 2) {$ExitCode = 1}
}

Write-Log -Message "Script finished. Setting exit code to $ExitCode."

# Final exit with the determined code
Exit $ExitCode
