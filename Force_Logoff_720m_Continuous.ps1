# Exit Codes:
# 0 - Script executed successfully.
# 1 - Script failed to get session details.
# 2 - User session was terminated (logged off) due to continuous use timeout.

# -------------------------------------------------------------
#                   ** CONFIGURATION BLOCK **
# -------------------------------------------------------------
$MaxContinuousHours = 12 # Set to 12 hours
$LogFileBaseName = "Logoff-Continuous"
$LogDirectory = "C:\temp"
$LogFilePath = "$LogDirectory\$LogFileBaseName_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
# -------------------------------------------------------------

function Write-Log {
    param([Parameter(Mandatory=$true)][string]$Message)
    # Ensure the script is completely silent
    [void](
        try {
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

# The entire execution block is wrapped in [void] to ensure complete silence.
[void](
    Write-Log "--- Continuous Logoff Script Start ---"
    Write-Log "Max Continuous Time: $MaxContinuousHours hours"

    try {
        # 1. Get current session details
        $SessionId = (Get-Process -PID $PID).SessionId
        $SessionInfo = Get-CimInstance -ClassName Win32_LogonSession | Where-Object { $_.LogonId -eq $SessionId }
        
        if (-not $SessionInfo) {
            Write-Log "ERROR: Could not retrieve current logon session information (LogonId: $SessionId)."
            exit 1
        }

        $LogonTime = [datetime]::ParseExact($SessionInfo.StartTime.Split('.')[0], "yyyyMMddHHmmss", $null)
        $ContinuousDuration = (Get-Date) - $LogonTime
        $ContinuousUseTimeout = $ContinuousDuration.TotalHours -ge $MaxContinuousHours
        $CurrentUsername = $SessionInfo.LogonToAccount

        Write-Log "Session for User '$CurrentUsername' (ID: $SessionId)."
        Write-Log "Logon Time: $LogonTime | Duration: $($ContinuousDuration.TotalHours.ToString('N2')) hours"

        if ($ContinuousUseTimeout) {
            Write-Log "ACTION: Terminating session. Reason: Continuous use limit of $MaxContinuousHours hours exceeded."
            logoff $SessionId
            Write-Log "Session termination command executed."
            Write-Log "--- Script End ---"
            exit 2
        } else {
            Write-Log "STATUS: Continuous use limit not met. Session remains active."
            Write-Log "--- Script End ---"
            exit 0
        }

    } catch {
        Write-Log "FATAL ERROR: $($_.Exception.Message)"
        Write-Log "--- Script End ---"
        exit 1
    }
)