# Exit Codes:
# 0 - Script executed successfully, both tasks created/updated.
# 1 - Fatal error (e.g., required script files missing).
# 2 - One of the tasks failed to create, but one or both scripts existed.

# -------------------------------------------------------------
#                   ** CONFIGURATION BLOCK **
# -------------------------------------------------------------
# *** UPDATED PATH TO THE NEW LOCATION ***
$LogoffScriptDirectory = "C:\Program Files (x86)\ManageEngine\UEMS_Agent\scripts" 
# NOTE: File names simplified to avoid shell execution errors (no dashes or parentheses)
$IdleScriptName = "Force_Logoff_60m_Inactive.ps1"
$ContinuousScriptName = "Force_Logoff_720m_Continuous.ps1"

$IdleTaskName = "Session Manager - 1. Idle Logoff (60m)"
$ContinuousTaskName = "Session Manager - 2. Continuous Logoff (12h)"

$LogFileBaseName = "Create-AllLogoffTasks"
$LogDirectory = "C:\temp"
$LogFilePath = "$LogDirectory\$LogFileBaseName_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
# -------------------------------------------------------------

$OverallSuccess = $true

function Write-Log {
    param([Parameter(Mandatory=$true)][string]$Message)
    # Ensure the script is completely silent
    [void](
        try {
            # Ensure the log directory exists
            if (-not (Test-Path -Path $LogDirectory)) {
                New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
            }
            $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            "$Timestamp - $Message" | Out-File -FilePath $LogFilePath -Append -Encoding UTF8
        } catch {
            # Silent fail for logging
        }
    )
}

function Create-Task {
    param(
        [Parameter(Mandatory=$true)][string]$ScriptFile,
        [Parameter(Mandatory=$true)][string]$TaskName
    )
    
    $ScriptPath = Join-Path -Path $LogoffScriptDirectory -ChildPath $ScriptFile

    Write-Log "Attempting to create task: '$TaskName' for script: '$ScriptPath'"

    if (-not (Test-Path -Path $ScriptPath -PathType Leaf)) {
        Write-Log "ERROR: Script file not found: '$ScriptPath'. Skipping task creation."
        return $false
    }
    
    # Task Action: Runs PowerShell hidden, bypassing policy, executing the target script.
    # The full path is enclosed in single quotes (') for the -File argument to handle spaces,
    # and the entire argument list is enclosed in double quotes (") for the schtasks /tr argument.
    $TaskAction = "powershell.exe -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File '$ScriptPath'"
    
    # schtasks command: Run every 5 minutes, under SYSTEM, only when user is logged on (/IT).
    $TaskCommand = "schtasks /create /tn `"$TaskName`" /tr `"$TaskAction`" /sc MINUTE /mo 5 /ru SYSTEM /IT /f"

    try {
        # Use Invoke-Expression and Out-String to capture and suppress schtasks output
        # The entire execution is wrapped in [void] to ensure complete silence.
        $Result = Invoke-Expression $TaskCommand 2>&1 | Out-String # Include stderr in $Result capture
        
        # Check for non-zero exit code or error messages
        if ($LASTEXITCODE -ne 0 -or $Result -match "ERROR" -or $Result -match "FAILURE") {
            Write-Log "ERROR: schtasks failed for task '$TaskName'."
            Write-Log "schtasks output: $Result"
            return $false
        } else {
            Write-Log "SUCCESS: Task '$TaskName' created/updated successfully."
            return $true
        }

    } catch {
        Write-Log "FATAL ERROR during schtasks execution for '$TaskName': $($_.Exception.Message)"
        return $false
    }
}

# The entire execution block is wrapped in [void] to ensure complete silence.
[void](
    Write-Log "--- Script Start: Creating Both Scheduled Tasks ---"

    # --- 1. Create Idle Logoff Task ---
    $IdleTaskResult = Create-Task -ScriptFile $IdleScriptName -TaskName $IdleTaskName
    if (-not $IdleTaskResult) {
        $OverallSuccess = $false
    }

    # --- 2. Create Continuous Logoff Task ---
    $ContinuousTaskResult = Create-Task -ScriptFile $ContinuousScriptName -TaskName $ContinuousTaskName
    if (-not $ContinuousTaskResult) {
        $OverallSuccess = $false
    }

    # --- Final Check and Exit ---
    if (-not $OverallSuccess) {
        # Check if files existed, to determine exit code 1 (fatal) or 2 (partial success/warning)
        $IdleFileExists = Test-Path -Path (Join-Path -Path $LogoffScriptDirectory -ChildPath $IdleScriptName)
        $ContinuousFileExists = Test-Path -Path (Join-Path -Path $LogoffScriptDirectory -ChildPath $ContinuousScriptName)

        if ($IdleFileExists -and $ContinuousFileExists) {
            Write-Log "WARNING: One or more tasks failed to create, but both script files were present. Check log for details."
            Write-Log "--- Script End ---"
            exit 2
        } else {
            Write-Log "FATAL: One or more required script files were missing. No tasks fully deployed."
            Write-Log "--- Script End ---"
            exit 1
        }
    } else {
        Write-Log "SUCCESS: Both scheduled tasks were created/updated successfully."
        Write-Log "--- Script End ---"
        exit 0
    }
)