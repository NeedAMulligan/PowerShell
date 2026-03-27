<#
.SYNOPSIS
    Dell Command | Update 5.6.0 - Local Upgrade & Config (Excluding BIOS)
.DESCRIPTION
    1. Verifies Dell Hardware & Version 5.6.0.
    2. Upgrades silently if version is < 5.6.0.
    3. Configures local policy (Weekly Thu @ 10AM) EXCLUDING BIOS updates.
    4. Triggers an immediate scan for drivers/system updates only.
.NOTES
    Optimized for ManageEngine Endpoint Central (System Context).
#>

# ==============================================================================
# 1. VARIABLES & CONFIGURATION
# ==============================================================================
$TargetVersion  = "5.6.0"
$DownloadUrl    = "https://dl.dell.com/FOLDER13922692M/1/Dell-Command-Update-Windows-Universal-Application_2WT0J_WIN64_5.6.0_A00.EXE"
$InstallerName  = "Dell-Command-Update-5.6.0.exe"
$LogDir         = "C:\temp"
$Timestamp      = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile        = Join-Path $LogDir "DCU_Upgrade_5.6_$($Timestamp).log"
$InstallerPath  = Join-Path $env:TEMP $InstallerName
$DcuCliPath     = "${env:ProgramFiles}\Dell\CommandUpdate\dcu-cli.exe"
$GlobalExitCode = 0

# ==============================================================================
# 2. LOGGING FUNCTION
# ==============================================================================
function Write-Log {
    param([string]$Message, [ValidateSet("INFO", "WARN", "ERROR")] $Level = "INFO")
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    $Entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Add-Content -Path $LogFile -Value $Entry
}

# ==============================================================================
# 3. PRE-FLIGHT CHECKS
# ==============================================================================
$Manufacturer = (Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer
if ($Manufacturer -notlike "*Dell*") {
    Write-Log "Non-Dell Hardware detected ($Manufacturer). Aborting." "ERROR"
    exit 1001 
}

# Check Current Version via Registry
$RegKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", 
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
$CurrentVersion = Get-ItemProperty $RegKeys -ErrorAction SilentlyContinue | 
                  Where-Object { $_.DisplayName -like "*Dell Command | Update*" } | 
                  Select-Object -ExpandProperty DisplayVersion -First 1

if ($CurrentVersion -eq $TargetVersion) {
    Write-Log "Version $TargetVersion already present. Skipping installation."
} else {
    # ==============================================================================
    # 4. DOWNLOAD & INSTALLATION
    # ==============================================================================
    if (Get-Process "msiexec" -ErrorAction SilentlyContinue) {
        Write-Log "MSI Installer busy (1618). Aborting." "ERROR"
        exit 1618
    }

    try {
        Write-Log "Downloading DCU 5.6.0 from Dell..."
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $InstallerPath -ErrorAction Stop
        
        Write-Log "Starting Silent Upgrade (Current: $CurrentVersion)..."
        $Process = Start-Process -FilePath $InstallerPath -ArgumentList "/s /f" -Wait -PassThru
        
        if ($Process.ExitCode -eq 3010) {
            Write-Log "Install Successful - Reboot Pending (3010)." "WARN"
            $GlobalExitCode = 3010
        } elseif ($Process.ExitCode -ne 0) {
            Write-Log "Installer failed with code $($Process.ExitCode)." "ERROR"
            exit 1003
        } else {
            Write-Log "Installation of version 5.6.0 completed successfully."
        }
    } catch {
        Write-Log "Critical error during download/install: $($_.Exception.Message)" "ERROR"
        exit 1002
    } finally {
        if (Test-Path $InstallerPath) { Remove-Item $InstallerPath -Force -ErrorAction SilentlyContinue }
    }
}

# ==============================================================================
# 5. CONFIGURATION & IMMEDIATE SCAN (EXCLUDING BIOS)
# ==============================================================================
if (Test-Path $DcuCliPath) {
    Write-Log "Applying Weekly Schedule and Policies (EXCLUDING BIOS)..."
    
    # Note: 'bios' removed from -updateType
    $ConfigArgs = @(
        "/configure",
        "-scheduleWeekly=Thu",
        "-scheduleTime=10:00",
        "-updateType=sys,driver", 
        "-bitlockerSuspend=enable",
        "-userConsent=disable",
        "-reboot=disable"
    )
    $ConfigProc = Start-Process -FilePath $DcuCliPath -ArgumentList $ConfigArgs -Wait -PassThru
    Write-Log "Policy Configuration Exit Code: $($ConfigProc.ExitCode)"

    Write-Log "Triggering Immediate Scan (Excluding BIOS updates)..."
    $ScanProcess = Start-Process -FilePath $DcuCliPath -ArgumentList "/scan" -Wait -NoNewWindow -PassThru
    Write-Log "Immediate scan completed with Exit Code: $($ScanProcess.ExitCode)"
} else {
    Write-Log "DCU CLI not found at $DcuCliPath. Configuration failed." "ERROR"
    exit 1004
}

Write-Log "Script Execution Finished."
exit $GlobalExitCode