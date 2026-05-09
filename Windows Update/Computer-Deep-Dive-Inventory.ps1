<#
.SYNOPSIS
    Master Onboarding Discovery Script - Combined Hardware, Users, & Peripherals.
.DESCRIPTION
    Aggregates System Specs, Local Users, Storage, Network Shares, Printers, and Scanners.
    Adds (COMPUTER) name as the first column for easy CSV merging.
    Designed for silent execution in SYSTEM context.
    Outputs to C:\temp\Master_Onboarding_YYYYMMDD.csv
.PARAMETER None
.EXAMPLE
    .\Get-MasterOnboarding.ps1
#>

# --------------------------------------------------------------------------
# VARIABLES & CONFIGURATION
# --------------------------------------------------------------------------
$ComputerName = $env:COMPUTERNAME
$LogDir       = "C:\temp"
$Timestamp    = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile      = Join-Path $LogDir "Master_Onboarding_$($Timestamp).log"
$CsvFile      = Join-Path $LogDir "Master_Onboarding_$($Timestamp).csv"
$ErrorActionPreference = "Stop"

# --------------------------------------------------------------------------
# EXIT CODES
# 0 = Success | 1 = General Failure
# --------------------------------------------------------------------------

function Write-Log {
    param([string]$Message)
    $Stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$Stamp] $Message" | Add-Content -Path $LogFile -ErrorAction SilentlyContinue
}

try {
    if (-not (Test-Path $LogDir)) { New-Item $LogDir -ItemType Directory -Force }
    Write-Log "Starting Master Onboarding Discovery for ($ComputerName)..."
    
    $MasterResults = @()

    # --- 1. SYSTEM HARDWARE SUMMARY ---
    Write-Log "Querying Hardware Specs..."
    $OS = Get-CimInstance Win32_OperatingSystem
    $CS = Get-CimInstance Win32_ComputerSystem
    $MasterResults += [PSCustomObject]@{
        "(COMPUTER)" = $ComputerName
        Category     = "System Info"
        ItemName     = "OS & Hardware"
        Details      = "OS: $($OS.Caption) | RAM: $([Math]::Round($CS.TotalPhysicalMemory / 1GB, 0))GB | Model: $($CS.Model)"
        Status       = "Version: $($OS.Version)"
    }

    # --- 2. LOCAL USERS ---
    Write-Log "Querying Local Accounts..."
    Get-LocalUser | ForEach-Object {
        $MasterResults += [PSCustomObject]@{
            "(COMPUTER)" = $ComputerName
            Category     = "Local User"
            ItemName     = $_.Name
            Details      = "LastLogon: $($_.LastLogon)"
            Status       = if ($_.Enabled) { "Enabled" } else { "Disabled" }
        }
    }

    # --- 3. STORAGE USAGE ---
    Write-Log "Querying Logical Disks..."
    Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
        $MasterResults += [PSCustomObject]@{
            "(COMPUTER)" = $ComputerName
            Category     = "Storage"
            ItemName     = $_.DeviceID
            Details      = "Total: $([Math]::Round($_.Size/1GB,2))GB | Free: $([Math]::Round($_.FreeSpace/1GB,2))GB"
            Status       = "$([Math]::Round(($_.FreeSpace/$_.Size)*100,0))% Free"
        }
    }

    # --- 4. NETWORK SHARES ---
    Write-Log "Querying Active Shares..."
    Get-CimInstance Win32_Share -Filter "Type=0" | ForEach-Object {
        $MasterResults += [PSCustomObject]@{
            "(COMPUTER)" = $ComputerName
            Category     = "Network Share"
            ItemName     = $_.Name
            Details      = "Path: $($_.Path)"
            Status       = "Active"
        }
    }

    # --- 5. PRINTERS (Registry Deep Scan with Error Handling) ---
    Write-Log "Querying Installed Printers..."
    $PrinterKeys = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\Printers" -ErrorAction SilentlyContinue
    foreach ($Key in $PrinterKeys) {
        $PortInfo = "Unknown Port"
        try {
            # Attempt to get the Port property without crashing if it's missing
            $PortInfo = Get-ItemPropertyValue $Key.PSPath -Name "Port" -ErrorAction Stop
        } catch {
            $PortInfo = "Port Info Not Found"
        }

        $MasterResults += [PSCustomObject]@{
            "(COMPUTER)" = $ComputerName
            Category     = "Printer"
            ItemName     = $Key.PSChildName
            Details      = "Port: $PortInfo"
            Status       = "Registry Entry Found"
        }
    }

    # --- 6. SCANNERS & IMAGING ---
    Write-Log "Querying Imaging Hardware..."
    $Scanners = Get-CimInstance Win32_PnPEntity | Where-Object { 
        $_.PNPClass -eq "Image" -or $_.Description -match "Scanner|ScanJet|LaserJet|Fujitsu" 
    }
    foreach ($Dev in $Scanners) {
        $MasterResults += [PSCustomObject]@{
            "(COMPUTER)" = $ComputerName
            Category     = "Imaging Device"
            ItemName     = $Dev.Name
            Details      = "Manufacturer: $($Dev.Manufacturer)"
            Status       = $Dev.Status
        }
    }

    # --- FINAL EXPORT ---
    $MasterResults | Export-Csv -Path $CsvFile -NoTypeInformation -Encoding UTF8
    Write-Log "Master Discovery Complete. Found $($MasterResults.Count) entries."
    exit 0

} catch {
    Write-Log "FATAL ERROR: $($_.Exception.Message)"
    exit 1
}