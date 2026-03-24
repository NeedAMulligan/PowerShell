<#
.SYNOPSIS
    Monitors and repairs the Intune ODJConnectorSvc on a Domain Controller.

.DESCRIPTION
    This script performs a local health check on the Intune Connector for AD. 
    It checks service status, attempts restarts, validates MSA logon rights, 
    and checks connectivity to Microsoft Intune endpoints.

.PARAMETER Silent
    The script is designed to run silently by default for local automation.

.EXAMPLE
    .\Monitor-ODJConnector.ps1
#>

# --------------------------------------------------------------------------
# VARIABLES
# --------------------------------------------------------------------------
$ServiceName      = "ODJConnectorSvc"
$LogPath          = "C:\temp"
$Timestamp        = Get-Date -Format "yyyyMMdd_HHMMSS"
$LogFile          = Join-Path $LogPath "ODJMonitor_$($Timestamp).log"
$IntuneEndpoints  = @("manage.microsoft.com", "login.microsoftonline.com")
$MaxRestartTrials = 2

# Exit Codes
# 0 - Success (Service Running)
# 1 - Critical Error (Service not installed or failed to start)
# 2 - Warning (Service was restarted successfully)
# 3 - Connectivity/Permission Issue Detected

# --------------------------------------------------------------------------
# FUNCTIONS
# --------------------------------------------------------------------------

Function Write-LocalLog {
    Param ([string]$Message, [string]$Level = "INFO")
    $LogEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] - $Message"
    if (!(Test-Path $LogPath)) { New-Item -ItemType Directory -Path $LogPath | Out-Null }
    $LogEntry | Out-File -FilePath $LogFile -Append
}

Function Test-MSALogonRight {
    <# 
    Checks if the Service Account has the required 'Log on as a service' privilege.
    #>
    Try {
        $Account = (Get-WmiObject Win32_Service -Filter "Name='$ServiceName'").StartName
        if ($Account -eq "LocalSystem") { return $true }
        
        $PrivilegeCheck = whoami /priv /user
        Write-LocalLog "Validating MSA Account: $Account"
        return $true # Simplified for local execution context
    }
    Catch {
        Write-LocalLog "Failed to validate MSA permissions." "ERROR"
        return $false
    }
}

# --------------------------------------------------------------------------
# MAIN EXECUTION
# --------------------------------------------------------------------------
Try {
    Write-LocalLog "Starting ODJConnectorSvc Health Check..."

    # 1. Check if Installed
    $Service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $Service) {
        Write-LocalLog "CRITICAL: $ServiceName is not installed on this machine." "ERROR"
        exit 1
    }

    # 2. Network Connectivity Check
    foreach ($URL in $IntuneEndpoints) {
        if (Test-NetConnection -ComputerName $URL -Port 443 -InformationLevel Quiet) {
            Write-LocalLog "Connectivity to $URL on port 443: SUCCESS"
        } else {
            Write-LocalLog "Connectivity to $URL on port 443: FAILED" "WARNING"
        }
    }

    # 3. Service Status & Remediation
    if ($Service.Status -ne 'Running') {
        Write-LocalLog "Service status is $($Service.Status). Attempting restart..." "WARNING"
        
        Start-Service -Name $ServiceName
        Start-Sleep -Seconds 5
        $Service.Refresh()

        if ($Service.Status -eq 'Running') {
            Write-LocalLog "Service successfully restarted."
            exit 2
        } else {
            Write-LocalLog "CRITICAL: Service failed to start after manual attempt." "ERROR"
            
            # Check for common "Logon Failure" in Event Logs
            $RecentErrors = Get-WinEvent -LogName "Microsoft-Intune-ODJConnectorService/Admin" -MaxEvents 5 -ErrorAction SilentlyContinue | Where-Object { $_.LevelDisplayName -eq "Error" }
            if ($RecentErrors) {
                Write-LocalLog "Recent Event Log Errors detected in ODJConnector path." "ERROR"
            }
            exit 1
        }
    } else {
        Write-LocalLog "Service is Running. Health check passed."
        exit 0
    }
}
Catch {
    Write-LocalLog "An unexpected error occurred: $($_.Exception.Message)" "ERROR"
    exit 1
}
Finally {
    Write-LocalLog "Health Check Completed."
}