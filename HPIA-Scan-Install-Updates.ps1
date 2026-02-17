<#
Custom Exit Codes:
0    = Success
3010 = Success (Reboot Required)
1001 = Failed to load/install HP CMSL Module
1002 = HPIA Download/Extraction Failed
1003 = Hardware not supported (Non-HP)
1004 = HPIA Analysis/Install Error (Code 256)
1005 = Logging/Transcript Failure
#>

$ErrorActionPreference = "Stop"

# --- Step 0: Logging & Transcript Setup ---
$LogRoot = "C:\temp"
if (-not (Test-Path $LogRoot)) { New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null }

$TranscriptPath = Join-Path $LogRoot "HPIA_TRANSCRIPT.log"
$TimeStamp      = Get-Date -Format "yyyyMMdd_HHmmss"
$PublicLog      = Join-Path $LogRoot "HPIA_Managed_$TimeStamp.log"

try { Start-Transcript -Path $TranscriptPath -Append -Force } catch { exit 1005 }

function Write-Log {
    param([string]$Message)
    $CurrentTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$CurrentTime] $Message" | Out-File -FilePath $PublicLog -Append -ErrorAction SilentlyContinue
}

Write-Log "Initializing HP Image Assistant Managed Script."

# --- Step 1: Verify Hardware ---
try {
    $SysInfo = Get-CimInstance Win32_ComputerSystem
    if ($SysInfo.Manufacturer -notmatch "HP|Hewlett-Packard") {
        Write-Log "Error: Non-HP hardware detected. Exiting."
        Stop-Transcript
        exit 1003
    }
    $PlatformID = (Get-CimInstance Win32_BaseBoard).Product
    Write-Log "Hardware Verified: $($SysInfo.Model) (Platform $PlatformID)"
} catch { exit 1003 }

# --- Step 2: Directory Configuration ---
$BaseDir     = "C:\HPIA"
$ExtractDir  = Join-Path $BaseDir "App"
$DownloadDir = Join-Path $BaseDir "Softpaqs"
$WorkLogDir  = Join-Path $BaseDir "Reports"
$HPIA_Exe    = Join-Path $ExtractDir "HPImageAssistant.exe"

foreach ($Path in @($BaseDir, $ExtractDir, $DownloadDir, $WorkLogDir)) {
    if (-not (Test-Path $Path)) { New-Item $Path -ItemType Directory -Force | Out-Null }
}

# --- Step 3: Ensure HPIA is "Installed" (Staged) ---
try {
    if (-not (Test-Path $HPIA_Exe)) {
        Write-Log "HPIA not found in $ExtractDir. Downloading latest version..."
        
        # Ensure CMSL is available for download
        if (-not (Get-Module -ListAvailable -Name HPCMSL)) {
            Write-Log "Installing HPCMSL Module..."
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Install-Module -Name HPCMSL -Force -AllowClobber -Scope AllUsers -Confirm:$false
        }
        Import-Module HPCMSL -ErrorAction Stop

        # Download and Extract HPIA
        Install-HPImageAssistant -Extract -DestinationPath $ExtractDir -Quiet -ErrorAction SilentlyContinue
        
        if (-not (Test-Path $HPIA_Exe)) { throw "Failed to extract HPIA binary." }
        Write-Log "HPIA successfully staged at $HPIA_Exe"
    } else {
        Write-Log "HPIA already staged. Skipping download."
    }
} catch {
    Write-Log "Critical Error during HPIA setup: $($_.Exception.Message)"
    Stop-Transcript
    exit 1002
}

# --- Step 4: System Profile Prep (EULA) ---
try {
    $RegPaths = @("HKLM:\SOFTWARE\HP\HP Image Assistant", "HKCU:\Software\HP\HP Image Assistant")
    foreach ($P in $RegPaths) {
        if (-not (Test-Path $P)) { New-Item -Path $P -Force | Out-Null }
        Set-ItemProperty -Path $P -Name "AcceptEULA" -Value "Yes" -Force
    }
} catch { Write-Log "Registry warning: $($_.Exception.Message)" }

# --- Step 5: Execution ---
function Invoke-HPIASilent {
    param([string]$Arguments)
    $PSI = New-Object System.Diagnostics.ProcessStartInfo
    $PSI.FileName = $HPIA_Exe
    $PSI.Arguments = $Arguments
    $PSI.WindowStyle = "Hidden"
    $PSI.CreateNoWindow = $true
    $PSI.UseShellExecute = $false
    $PSI.WorkingDirectory = $ExtractDir
    
    Write-Log "Launching HPIA with: $Arguments"
    $Process = [System.Diagnostics.Process]::Start($PSI)
    $Process.WaitForExit()
    return $Process.ExitCode
}

$FinalExitCode = 1004
try {
    # We use /Analyze:All to force discovery without a hardcoded RefID
    $BaseArgs = "/Operation:Analyze /Action:Install /AutoSelect:All /Category:Drivers /Silent /NonInteractive /SkipApplicationUpdate /ReportFolder:""$WorkLogDir"" /SoftpaqDownloadFolder:""$DownloadDir"""
    
    $FinalExitCode = Invoke-HPIASilent -Arguments $BaseArgs

    # Fallback to 25H2 RefId if Discovery fails with 256
    if ($FinalExitCode -eq 256) {
        Write-Log "Standard Discovery failed (256). Attempting forced 25H2 Reference..."
        $FinalExitCode = Invoke-HPIASilent -Arguments "$BaseArgs /RefId:""25H2"" /Platform:""$PlatformID"""
    }
} catch {
    Write-Log "Execution Error: $($_.Exception.Message)"
} finally {
    # Move technical logs to C:\temp
    $InternalLog = Join-Path $ExtractDir "HPImageAssistant.log"
    if (Test-Path $InternalLog) {
        Copy-Item $InternalLog -Destination (Join-Path $LogRoot "HPIA_Technical_Full_$TimeStamp.log") -Force
    }

    # Final logic for RMM return codes
    $ExitToReturn = 1004
    if ($FinalExitCode -eq 3010) { $ExitToReturn = 3010 }
    elseif ($FinalExitCode -eq 0) { $ExitToReturn = 0 }

    if ($ExitToReturn -eq 0 -or $ExitToReturn -eq 3010) {
        Write-Log "Process Successful. Cleaning staging folder."
        Remove-Item -Path $BaseDir -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        Write-Log "Process Failed (HPIA Code: $FinalExitCode). Staging preserved at $BaseDir."
    }

    Write-Log "Script Finished. Final Return Code: $ExitToReturn"
    Stop-Transcript
    exit $ExitToReturn
}