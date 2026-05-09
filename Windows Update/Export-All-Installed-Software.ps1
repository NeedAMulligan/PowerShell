<#
.SYNOPSIS
    Deep Inventory of Win32 and Appx Applications.
.DESCRIPTION
    Scans Registry (HKLM 64/32 and HKCU) and Appx Packages for all users. 
    Designed for silent execution via SYSTEM context (e.g., ScreenConnect).
    Outputs a CSV and Log file to C:\temp.
.PARAMETER None
.EXAMPLE
    .\Get-LocalSoftwareInventory.ps1
#>

# --------------------------------------------------------------------------
# VARIABLES & CONFIGURATION
# --------------------------------------------------------------------------
$ScriptName   = "SoftwareInventory"
$LogDir       = "C:\temp"
$Timestamp    = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile      = Join-Path $LogDir "$($ScriptName)_$($Timestamp).log"
$CsvFile      = Join-Path $LogDir "$($ScriptName)_$($Timestamp).csv"
$ErrorActionPreference = "Stop"

# --------------------------------------------------------------------------
# EXIT CODES
# --------------------------------------------------------------------------
# 0 = Success
# 1 = General Error / Catch Block Triggered
# 2 = Directory Creation Failed
# --------------------------------------------------------------------------

# --------------------------------------------------------------------------
# FUNCTIONS
# --------------------------------------------------------------------------

function Write-Log {
    param([string]$Message, [ValidateSet("INFO", "WARN", "ERROR")] $Level = "INFO")
    $Stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Line = "[$Stamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $Line -ErrorAction SilentlyContinue
}

function Initialize-Environment {
    try {
        if (-not (Test-Path $LogDir)) {
            New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
        }
        Write-Log "Inventory started. Target CSV: $CsvFile"
    }
    catch {
        exit 2
    }
}

function Get-Win32Software {
    Write-Log "Scanning Registry for Win32 Applications..."
    $Paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $Results = foreach ($Path in $Paths) {
        Get-ItemProperty $Path -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -ne $null } | ForEach-Object {
            # Robust Date Formatting
            $RawDate = $_.InstallDate
            $FormattedDate = $null
            if ($RawDate -match '^\d{8}$') {
                $FormattedDate = "$($RawDate.Substring(0,4))-$($RawDate.Substring(4,2))-$($RawDate.Substring(6,2))"
            }

            [PSCustomObject]@{
                Name        = $_.DisplayName
                Version     = $_.DisplayVersion
                Publisher   = $_.Publisher
                InstallDate = $FormattedDate
                Type        = "Win32 (Registry)"
                Architecture = if ($_.PSPath -like "*WOW6432Node*") { "x86" } else { "x64" }
            }
        }
    }
    return $Results
}

function Get-AppxSoftware {
    Write-Log "Querying Appx Packages (All Users)..."
    try {
        $Appx = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | ForEach-Object {
            [PSCustomObject]@{
                Name        = $_.Name
                Version     = $_.Version
                Publisher   = $_.Publisher
                InstallDate = "N/A" # Appx doesn't reliably store install date in registry format
                Type        = "Appx (Windows Store)"
                Architecture = $_.Architecture
            }
        }
        return $Appx
    }
    catch {
        Write-Log "Failed to query Appx packages." "WARN"
        return @()
    }
}

# --------------------------------------------------------------------------
# MAIN EXECUTION BLOCK
# --------------------------------------------------------------------------

try {
    Initialize-Environment
    
    # Gather Data
    $Win32List = Get-Win32Software
    $AppxList  = Get-AppxSoftware
    
    # Combine and Filter Duplicates
    Write-Log "Processing and de-duplicating results..."
    $FullInventory = ($Win32List + $AppxList) | Sort-Object Name -Unique
    
    # Export to CSV
    $FullInventory | Export-Csv -Path $CsvFile -NoTypeInformation -Encoding UTF8
    
    Write-Log "Inventory Complete. Total Items Found: $($FullInventory.Count)"
    exit 0
}
catch {
    Write-Log "FATAL ERROR: $($_.Exception.Message)" "ERROR"
    exit 1
}