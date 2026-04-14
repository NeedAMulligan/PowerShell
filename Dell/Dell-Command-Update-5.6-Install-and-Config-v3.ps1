<#
.SYNOPSIS
    Dell Command | Update 5.6.0 - Local Upgrade & Config (Excluding BIOS)
.DESCRIPTION
    1. Verifies Dell Hardware & Version 5.6.0.
    2. Upgrades silently if version is < 5.6.0.
    3. Initializes Registry and Service environment (The Fix).
    4. Configures local policy (Weekly Thu @ 10AM) EXCLUDING BIOS updates.
    5. Triggers an immediate scan for drivers/system updates only.
#>

# ==============================================================================
# 1. VARIABLES & CONFIGURATION
# ==============================================================================
$Variables = @{
    TargetVersion    = "5.6.0"
    DownloadUrl      = "https://dl.dell.com/FOLDER13922692M/1/Dell-Command-Update-Windows-Universal-Application_2WT0J_WIN64_5.6.0_A00.EXE"
    InstallerName    = "Dell-Command-Update-5.6.0.exe"
    LogDir           = "C:\temp"
    Timestamp        = Get-Date -Format "yyyyMMdd_HHmmss"
    DcuCliPath       = "${env:ProgramFiles}\Dell\CommandUpdate\dcu-cli.exe"
    DcuService       = "DellClientManagementService"
    RegistrySettings = "HKLM:\SOFTWARE\Dell\UpdateService\Settings"
}

$LogFile = Join-Path $Variables.LogDir "DCU_Upgrade_5.6_$($Variables.Timestamp).log"
$InstallerPath = Join-Path $env:TEMP $Variables.InstallerName
$GlobalExitCode = 0

# ==============================================================================
# 2. LOGGING FUNCTION
# ==============================================================================
function Write-LocalLog {
    param([string]$Message, [ValidateSet("INFO", "WARN", "ERROR")] $Level = "INFO")
    if (-not (Test-Path $Variables.LogDir)) { New-Item -ItemType Directory -Path $Variables.LogDir -Force | Out-Null }
    
    # Use ${} to prevent Drive Provider errors with the colon
    $Entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [${Level}] $Message"
    Add-Content -Path $LogFile -Value $Entry
}

# ==============================================================================
# 3. PRE-FLIGHT CHECKS
# ==============================================================================
$Manufacturer = (Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer
if ($Manufacturer -notlike "*Dell*") {
    Write-LocalLog "Non-Dell Hardware detected ($Manufacturer). Aborting." "ERROR"
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

if ($CurrentVersion -eq $Variables.TargetVersion) {
    Write-LocalLog "Version $($Variables.TargetVersion) already present. Proceeding to config check."
} else {
    # ==============================================================================
    # 4. DOWNLOAD & INSTALLATION
    # ==============================================================================
    if (Get-Process "msiexec" -ErrorAction SilentlyContinue) {
        Write-LocalLog "MSI Installer busy (1618). Aborting." "ERROR"
        exit 1618
    }

    try {
        Write-LocalLog "Downloading DCU 5.6.0 from Dell..."
        Invoke-WebRequest -Uri $Variables.DownloadUrl -OutFile $InstallerPath -ErrorAction Stop
        
        Write-LocalLog "Starting Silent Upgrade (Current: $CurrentVersion)..."
        $Process = Start-Process -FilePath $InstallerPath -ArgumentList "/s /f" -Wait -PassThru
        
        if ($Process.ExitCode -eq 3010) {
            Write-LocalLog "Install Successful - Reboot Pending (3010)." "WARN"
            $GlobalExitCode = 3010
        } elseif ($Process.ExitCode -ne 0) {
            Write-LocalLog "Installer failed with code $($Process.ExitCode)." "ERROR"
            exit 1003
        } else {
            Write-LocalLog "Installation of version 5.6.0 completed successfully."
        }
    } catch {
        Write-LocalLog "Critical error during download/install: $($_.Exception.Message)" "ERROR"
        exit 1002
    } finally {
        if (Test-Path $InstallerPath) { Remove-Item $InstallerPath -Force -ErrorAction SilentlyContinue }
    }
}

# ==============================================================================
# 5. ENVIRONMENT INITIALIZATION (THE REGISTRY FIX)
# ==============================================================================
if (Test-Path $Variables.DcuCliPath) {
    # Ensure Service is running
    $Service = Get-Service -Name $Variables.DcuService -ErrorAction SilentlyContinue
    if ($null -ne $Service -and $Service.Status -ne 'Running') {
        Write-LocalLog "Starting $($Variables.DcuService) to initialize environment..."
        Start-Service -Name $Variables.DcuService -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
    }

    # Manually initialize registry if missing to prevent CLI "Exit Code 2"
    if (-not (Test-Path $Variables.RegistrySettings)) {
        Write-LocalLog "Registry settings path missing. Initializing manually..." "WARN"
        New-Item -Path "HKLM:\SOFTWARE\Dell\UpdateService" -Name "Settings" -Force | Out-Null
        
        # Trigger policy handshake
        Start-Process -FilePath $Variables.DcuCliPath -ArgumentList "/policy" -Wait -WindowStyle Hidden
        Write-LocalLog "Registry initialization sequence completed."
    }

    # ==============================================================================
    # 6. CONFIGURATION & IMMEDIATE SCAN (EXCLUDING BIOS)
    # ==============================================================================
    Write-LocalLog "Applying Weekly Schedule and Policies (EXCLUDING BIOS)..."
    $ConfigArgs = @(
        "/configure",
        "-scheduleWeekly=Thu",
        "-scheduleTime=10:00",
        "-updateType=sys,driver", 
        "-bitlockerSuspend=enable",
        "-userConsent=disable",
        "-reboot=disable"
    )
    $ConfigProc = Start-Process -FilePath $Variables.DcuCliPath -ArgumentList $ConfigArgs -Wait -PassThru -WindowStyle Hidden
    Write-LocalLog "Policy Configuration Exit Code: $($ConfigProc.ExitCode)"

    Write-LocalLog "Triggering Immediate Scan (Excluding BIOS updates)..."
    $ScanProcess = Start-Process -FilePath $Variables.DcuCliPath -ArgumentList "/scan" -Wait -PassThru -WindowStyle Hidden
    Write-LocalLog "Immediate scan completed with Exit Code: $($ScanProcess.ExitCode)"
} else {
    Write-LocalLog "DCU CLI not found at $($Variables.DcuCliPath). Configuration failed." "ERROR"
    exit 1004
}

Write-LocalLog "Script Execution Finished Successfully."
exit $GlobalExitCode