# Exit Codes:
# 0 - Script executed successfully.
# 1 - Script failed to get session details or user idle time.
# 2 - User session was terminated (logged off) due to inactivity timeout.

# -------------------------------------------------------------
#                   ** CONFIGURATION BLOCK **
# -------------------------------------------------------------
$MaxIdleMinutes = 60 # Set to 60 minutes (1 hour)
$LogFileBaseName = "Logoff-Idle"
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

function Get-IdleTime {
    Add-Type -TypeDefinition @'
        using System;
        using System.Runtime.InteropServices;
        
        public class IdleTime {
            [StructLayout(LayoutKind.Sequential)]
            private struct LASTINPUTINFO {
                public uint cbSize;
                public uint dwTime;
            }
            [DllImport("user32.dll")]
            private static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
            
            public static uint GetIdleTimeSeconds() {
                LASTINPUTINFO lastInputInfo = new LASTINPUTINFO();
                lastInputInfo.cbSize = (uint)Marshal.SizeOf(lastInputInfo);
                if (GetLastInputInfo(ref lastInputInfo)) {
                    uint idleTimeMs = (uint)Environment.TickCount - lastInputInfo.dwTime;
                    return idleTimeMs / 1000;
                } else { return 0; }
            }
        }
'@
    [IdleTime]::GetIdleTimeSeconds()
}

# The entire execution block is wrapped in [void] to ensure complete silence.
[void](
    Write-Log "--- Idle Logoff Script Start ---"
    Write-Log "Max Idle Time: $MaxIdleMinutes minutes"

    try {
        $SessionId = (Get-Process -PID $PID).SessionId
        $IdleTimeSeconds = Get-IdleTime
        $IdleDuration = [TimeSpan]::FromSeconds($IdleTimeSeconds)
        $IdleTimeout = $IdleDuration.TotalMinutes -ge $MaxIdleMinutes

        Write-Log "Session ID: $SessionId | Idle Duration: $($IdleDuration.TotalMinutes.ToString('N2')) minutes"

        if ($IdleTimeout) {
            Write-Log "ACTION: Terminating session. Reason: Inactivity limit of $MaxIdleMinutes minutes exceeded."
            logoff $SessionId
            Write-Log "Session termination command executed."
            Write-Log "--- Script End ---"
            exit 2
        } else {
            Write-Log "STATUS: Inactivity limit not met. Session remains active."
            Write-Log "--- Script End ---"
            exit 0
        }

    } catch {
        Write-Log "FATAL ERROR: $($_.Exception.Message)"
        Write-Log "--- Script End ---"
        exit 1
    }
)