<#
.SYNOPSIS
    Recursively sets Dropbox folders to "Online-Only" for all user profiles on a machine.
    
.DESCRIPTION
    0    = Success (or no Dropbox installs found to process)
    1001 = Pathing Error
    1005 = General Execution Failure
#>

$ErrorActionPreference = "Stop"

# Exit Codes
$EXIT_SUCCESS = 0
$EXIT_PATH_ERR = 1001
$EXIT_ERROR = 1005

# Logging Setup
$LogDir = "C:\temp"
if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory | Out-Null }
$LogFile = Join-Path $LogDir "Global-DropboxSmartSync_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Write-Log {
    param([string]$Message)
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$TimeStamp - $Message" | Out-File -FilePath $LogFile -Append
}

Write-Log "Starting Global Smart Sync Application (SYSTEM Context)"

try {
    # Get all user folders excluding system accounts
    $UserProfiles = Get-ChildItem "C:\Users" -Directory | Where-Object { $_.Name -notmatch "Public|Default|All Users" }

    foreach ($Profile in $UserProfiles) {
        $UserName = $Profile.Name
        $InfoPath = "$($Profile.FullName)\AppData\Local\Dropbox\info.json"

        if (Test-Path $InfoPath) {
            Write-Log "Found Dropbox config for user: $UserName"
            
            try {
                $DropboxInfo = Get-Content $InfoPath -Raw | ConvertFrom-Json
                
                # Dropbox info.json can contain 'business' and 'personal' objects
                $PathsToProcess = @()
                if ($null -ne $DropboxInfo.business) { $PathsToProcess += $DropboxInfo.business.path }
                if ($null -ne $DropboxInfo.personal) { $PathsToProcess += $DropboxInfo.personal.path }

                foreach ($DbPath in $PathsToProcess) {
                    if (Test-Path $DbPath) {
                        Write-Log "Applying Online-Only attribute to: $DbPath"
                        
                        # +U = Unpinned (Cloud files only)
                        # /s = Process files in current and subfolders
                        # /d = Process folders as well
                        $AttribArgs = "+U /s /d `"$DbPath\*`""
                        $Process = Start-Process -FilePath "attrib.exe" -ArgumentList $AttribArgs -NoNewWindow -Wait -PassThru
                        
                        if ($Process.ExitCode -eq 0) {
                            Write-Log "Successfully updated attributes for $UserName"
                        } else {
                            Write-Log "Attrib.exe returned non-zero code for $UserName : $($Process.ExitCode)"
                        }
                    }
                }
            }
            catch {
                Write-Log "Failed to parse info.json or apply attributes for $UserName : $($_.Exception.Message)"
            }
        }
    }

    Write-Log "Global execution finished."
    exit $EXIT_SUCCESS

}
catch {
    Write-Log "Critical Script Failure: $($_.Exception.Message)"
    exit $EXIT_ERROR
}