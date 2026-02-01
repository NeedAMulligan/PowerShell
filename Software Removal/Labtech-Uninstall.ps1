# Exit Codes
$global:ExitCode_Success = 0
$global:ExitCode_NoAgentFound = 1001
$global:ExitCode_UninstallFailed = 1002
$global:ExitCode_CleanupPartial = 1003
$global:ExitCode_GeneralError = 1004

# --- Logging Setup (Must run first) ---
$LogDirectory = "C:\temp"
$ScriptName = $MyInvocation.MyCommand.Name
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile = Join-Path -Path $LogDirectory -ChildPath "$($ScriptName)_$($Timestamp).log"

# Create log directory if it doesn't exist
try {
    if (-not (Test-Path $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }
}
catch {
    # If C:\temp creation fails, log to the console (RMM log) and exit.
    Write-Host "ERROR: Could not create log directory $LogDirectory. $($_.Exception.Message)"
    exit $global:ExitCode_GeneralError
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $Time = Get-Date -Format "HH:mm:ss"
    $LogEntry = "[$Time] [$Level] $Message"
    Add-Content -Path $LogFile -Value $LogEntry
    # Write to host for RMM real-time visibility, but silently
    Write-Host $LogEntry
}

# --- Service Definitions ---
$ServiceNames = @("LTSvc", "LTService")
$LabTechRegKey32 = "HKLM:\SOFTWARE\LabTech"
$LabTechRegKey64 = "HKLM:\SOFTWARE\WOW6432Node\LabTech"
$InstallPaths = @(
    "${env:ProgramFiles}\LabTech",
    "${env:ProgramFiles(x86)}\LabTech"
)
# This is a common product code for newer LabTech/Automate Agents.
$ProductCode = "{11F25E17-A968-45F4-A04B-83C3067EE23B}" 


Write-Log "--- Starting ConnectWise Automate Agent Removal Script ---"

# 1. Pre-check: Determine if the agent is installed.
try {
    $AgentInstalled = $false
    foreach ($svc in $ServiceNames) {
        if (Get-Service -Name $svc -ErrorAction SilentlyContinue) {
            $AgentInstalled = $true
            break
        }
    }

    if (-not $AgentInstalled) {
        Write-Log "WARNING: Agent services were not found. Performing file/registry cleanup anyway."
        # Do not exit yet, proceed to cleanup just in case.
    }
}
catch {
    Write-Log "ERROR: Failed during initial service check. $($_.Exception.Message)" "ERROR"
    # Continue to try and clean up artifacts
}

# 2. Stop and Disable Services
Write-Log "Attempting to stop and disable ConnectWise Automate services..."
foreach ($ServiceName in $ServiceNames) {
    try {
        $Service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($Service) {
            if ($Service.Status -ne 'Stopped') {
                Stop-Service -InputObject $Service -Force -ErrorAction Stop
                Write-Log "Successfully stopped service: $ServiceName"
            }
            Set-Service -Name $ServiceName -StartupType Disabled -ErrorAction Stop
            Write-Log "Successfully disabled service: $ServiceName"
            
            # Attempt to delete the service entry
            sc.exe delete $ServiceName | Out-Null
            Write-Log "Attempted to delete service entry: $ServiceName"
        }
        else {
            Write-Log "Service $ServiceName not found."
        }
    }
    catch {
        Write-Log "ERROR: Could not stop, disable, or delete service $ServiceName. $($_.Exception.Message)" "ERROR"
    }
}

# 3. Standard Uninstall via MSIExec (Best Practice)
Write-Log "Attempting standard application uninstall via msiexec..."
try {
    # Check for the product code, if found, attempt silent uninstall
    $InstallInfo = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where-Object { $_.DisplayName -like "*ConnectWise Automate Agent*" }
    
    if ($InstallInfo) {
        $UninstallString = $InstallInfo.UninstallString
        
        if ($UninstallString -like "*.msi*") {
            # Use msiexec with /qn for silent and /norestart
            $msiexecArgs = "/x $($InstallInfo.PSChildName) /qn /norestart"
            Write-Log "Executing MSI uninstall: msiexec $msiexecArgs"
            
            $ExitCode = (Start-Process msiexec -ArgumentList $msiexecArgs -Wait -PassThru).ExitCode
            
            if ($ExitCode -eq 0) {
                Write-Log "MSI uninstall completed successfully (Exit Code 0)."
            }
            else {
                Write-Log "WARNING: MSI uninstall returned exit code $ExitCode. Proceeding with forced cleanup." "WARN"
                $UninstallFailed = $true
            }
        } else {
            Write-Log "WARNING: Found install entry but UninstallString was non-standard. Proceeding with forced cleanup." "WARN"
            $UninstallFailed = $true
        }
    } else {
        Write-Log "WARNING: No standard 'ConnectWise Automate Agent' entry found in Add/Remove Programs. Proceeding with forced cleanup." "WARN"
        $UninstallFailed = $true
    }
}
catch {
    Write-Log "ERROR: Standard uninstall process failed. $($_.Exception.Message). Proceeding with forced cleanup." "ERROR"
    $UninstallFailed = $true
}


# 4. Forced Cleanup (Files and Registry)
Write-Log "Starting forced cleanup of remaining files and registry entries..."
$CleanupPartial = $false

# A. Registry Cleanup
Write-Log "Cleaning up registry keys..."
$RegKeysToDelete = @($LabTechRegKey32, $LabTechRegKey64)
foreach ($KeyPath in $RegKeysToDelete) {
    try {
        if (Test-Path $KeyPath) {
            Remove-Item -Path $KeyPath -Recurse -Force -ErrorAction Stop
            Write-Log "Successfully removed registry key: $KeyPath"
        }
        else {
            Write-Log "Registry key not found: $KeyPath (Skipped)"
        }
    }
    catch {
        Write-Log "ERROR: Failed to remove registry key $KeyPath. $($_.Exception.Message)" "ERROR"
        $CleanupPartial = $true
    }
}

# B. File System Cleanup
Write-Log "Cleaning up installation directories..."
foreach ($Path in $InstallPaths) {
    try {
        if (Test-Path $Path) {
            Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
            Write-Log "Successfully removed directory: $Path"
        }
        else {
            Write-Log "Directory not found: $Path (Skipped)"
        }
    }
    catch {
        Write-Log "ERROR: Failed to remove directory $Path. $($_.Exception.Message)" "ERROR"
        $CleanupPartial = $true
    }
}


# --- Final Exit Decision ---
Write-Log "--- ConnectWise Automate Agent Removal Script Complete ---"

if ($UninstallFailed -or $CleanupPartial) {
    $FinalExitCode = $global:ExitCode_CleanupPartial
    Write-Log "WARNING: The removal was partially unsuccessful or required forced cleanup. Check the log for details." "WARN"
}
else {
    $FinalExitCode = $global:ExitCode_Success
    Write-Log "SUCCESS: The ConnectWise Automate agent appears to be completely removed."
}

exit $FinalExitCode
