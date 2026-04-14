<#
.SYNOPSIS
    Automates Dell Command | Update silently with registry initialization and logging.

.DESCRIPTION
    Checks for the DCU CLI, ensures the Dell Client Management Service is running, 
    initializes missing registry configurations to prevent failure, and runs an update apply.
    Optimized for silent, local execution.

.EXAMPLE
    .\Invoke-DellUpdateLocal.ps1
#>

# -------------------------------------------------------------------------
# VARIABLES
# -------------------------------------------------------------------------
$Variables = @{
    LogPath            = "C:\temp"
    LogName            = "DellUpdate_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    DcuCliPath         = "C:\Program Files\Dell\CommandUpdate\dcu-cli.exe"
    DcuService         = "DellClientManagementService"
    RegistrySettings   = "HKLM:\SOFTWARE\Dell\UpdateService\Settings"
    UpdateArgs         = "/applyUpdates -reboot=disable"
}

# -------------------------------------------------------------------------
# LOGGING FUNCTION
# -------------------------------------------------------------------------
function Write-LocalLog {
    param (
        [string]$Message,
        [ValidateSet("INFO", "ERROR", "WARN")]
        [string]$Level = "INFO"
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # Using ${} prevents "InvalidVariableReferenceWithDrive" error
    $LogEntry = "$Timestamp - ${Level}: $Message"
    
    if (-not (Test-Path $Variables.LogPath)) {
        try {
            New-Item -Path $Variables.LogPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        catch {
            return # Exit silently if logging directory cannot be created
        }
    }
    
    $LogFile = Join-Path $Variables.LogPath $Variables.LogName
    $LogEntry | Out-File -FilePath $LogFile -Append
}

# -------------------------------------------------------------------------
# INITIALIZATION FUNCTIONS
# -------------------------------------------------------------------------
function Initialize-DcuEnvironment {
    try {
        # 1. Verify Executable Path
        if (-not (Test-Path $Variables.DcuCliPath)) {
            Write-LocalLog "DCU CLI not found at $($Variables.DcuCliPath). Ensure Dell Command | Update is installed." "ERROR"
            exit 2
        }

        # 2. Verify and Start Dell Client Management Service
        $Service = Get-Service -Name $Variables.DcuService -ErrorAction SilentlyContinue
        if ($null -eq $Service) {
            Write-LocalLog "Required service $($Variables.DcuService) is not installed." "ERROR"
            exit 3
        }

        if ($Service.Status -ne 'Running') {
            Write-LocalLog "Service $($Variables.DcuService) is stopped. Attempting to start..." "INFO"
            Start-Service -Name $Variables.DcuService -ErrorAction Stop
            Start-Sleep -Seconds 5
        }

        # 3. Handle Missing Registry Key (The fix for your specific error)
        if (-not (Test-Path $Variables.RegistrySettings)) {
            Write-LocalLog "Registry key missing. Initializing path and triggering CLI handshake..." "WARN"
            
            # Force creation of the registry hive
            New-Item -Path "HKLM:\SOFTWARE\Dell\UpdateService" -Name "Settings" -Force -ErrorAction SilentlyContinue | Out-Null
            
            # Run a minor CLI command to force the service to populate default settings
            Start-Process -FilePath $Variables.DcuCliPath -ArgumentList "/policy" -Wait -WindowStyle Hidden
            
            Write-LocalLog "Registry initialization sequence completed." "INFO"
        }
    }
    catch {
        Write-LocalLog "Critical error during environment initialization: $($_.Exception.Message)" "ERROR"
        exit 1
    }
}

function Invoke-DcuUpdate {
    try {
        Write-LocalLog "Executing update scan and application..." "INFO"
        
        # Execute DCU CLI silently with provided arguments
        $Process = Start-Process -FilePath $Variables.DcuCliPath -ArgumentList $Variables.UpdateArgs -Wait -PassThru -WindowStyle Hidden
        
        # DCU Exit Codes: 0 = Success, 1 = Reboot Required, 2 = Error, 3 = No updates found
        switch ($Process.ExitCode) {
            0 { Write-LocalLog "Process finished. No updates needed or updates applied successfully." "INFO" }
            1 { Write-LocalLog "Updates applied successfully, but a system reboot is required." "WARN" }
            3 { Write-LocalLog "Scan completed: No applicable updates found for this system." "INFO" }
            Default { Write-LocalLog "DCU CLI returned exit code: $($Process.ExitCode)" "WARN" }
        }
    }
    catch {
        Write-LocalLog "Failed to execute update process: $($_.Exception.Message)" "ERROR"
        exit 1
    }
}

# -------------------------------------------------------------------------
# MAIN EXECUTION BLOCK
# -------------------------------------------------------------------------
try {
    Write-LocalLog "--- Script Execution Started (Silent Mode) ---" "INFO"
    
    Initialize-DcuEnvironment
    Invoke-DcuUpdate
    
    Write-LocalLog "--- Script Execution Finished ---" "INFO"
    exit 0
}
catch {
    Write-LocalLog "Unexpected Script Failure: $($_.Exception.Message)" "ERROR"
    exit 1
}
