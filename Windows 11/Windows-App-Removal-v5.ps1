<#
.SYNOPSIS
    Standardized MSP script for ManageEngine Endpoint Central to remove all specified 
    AppX packages for current and future users.
    
.DESCRIPTION
    1. Validates AppXSVC health.
    2. Performs Process Interference Check (Exits 1618 if apps are open).
    3. Removes Provisioned Packages (Future Users).
    4. Removes Installed Packages (All Existing Users).
    5. Logs activity to C:\Temp.

.EXITCODES
    0    - Success
    1    - General Error
    1001 - Service Error (AppXSVC)
    1618 - Process Interference (Target app is open)
#>

# --------------------------------------------------------------------------
# 1. VARIABLES & CONFIGURATION
# --------------------------------------------------------------------------
$LogDirectory = "C:\Temp"
$LogName      = "AppX_Removal_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd_HHmm').log"
$FullLogPath  = Join-Path $LogDirectory $LogName
$ErrorActionPreference = "Stop"

$AppsToRemove = @(
    # --- Social, Web & Productivity ---
    "*LinkedIn*", "*TikTok*", "*Instagram*", "SpotifyAB.SpotifyMusic", 
    "*Disney*", "king.com.CandyCrush*", "king.com.FarmHeroesSaga", 
    "Microsoft.WindowsJournal", "Microsoft.MicrosoftOfficeHub", 
    "Microsoft.BingFinance", "Microsoft.BingNews", "Microsoft.BingWeather",

    # --- New Windows Features & AI ---
    "Microsoft.Windows.Ai.Recall", "Microsoft.Copilot", 
    "Microsoft.Windows.DevHome", "Microsoft.PowerAutomateDesktop",

    # --- OEM Tools (Dell & HP) ---
    "DellInc.DellDigitalDelivery", "DellInc.DellOptimizer", 
    "AD2F1837.HPEasyClean", "AD2F1837.HPQuickDrop",

    # --- Communication & Support ---
    "Microsoft.OutlookForWindows", "microsoft.windowscommunicationsapps",
    "Microsoft.SkypeApp", "Microsoft.People", "Microsoft.YourPhone",
    "Microsoft.GetHelp", "Microsoft.Getstarted", "MicrosoftCorporationII.QuickAssist",
    "MicrosoftCorporationII.MicrosoftFamily",

    # --- Xbox & Gaming ---
    "Microsoft.GamingApp", "Microsoft.XboxApp", "Microsoft.Xbox.TCUI", 
    "Microsoft.XboxGameCallableUI", "Microsoft.XboxGameOverlay", 
    "Microsoft.XboxGamingOverlay", "Microsoft.XboxIdentityProvider", 
    "Microsoft.XboxOneSmartGlass", "Microsoft.XboxSpeechToTextOverlay",
    "Microsoft.MicrosoftSolitaireCollection",

    # --- Utilities & Media ---
    "Microsoft.ZuneMusic", "Microsoft.ZuneVideo", "Microsoft.WindowsMaps",
    "Microsoft.Print3D", "Microsoft.MixedReality.Portal",
    "Microsoft.WindowsFeedbackHub", "Microsoft.MicrosoftPaymentExperience",
    
    # --- Specific Bloat Stubs ---
    "*tile*", "*McAfee*"
)

# --------------------------------------------------------------------------
# 2. LOGGING & PRE-FLIGHT CHECKS
# --------------------------------------------------------------------------
if (!(Test-Path $LogDirectory)) { New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null }
Start-Transcript -Path $FullLogPath -Append

Write-Output "--------------------------------------------------------"
Write-Output "MSP CUSTOM SCRIPT: APPX REMOVAL v5.5"
Write-Output "Execution Time: $(Get-Date)"
Write-Output "Target System: $($env:COMPUTERNAME)"
Write-Output "--------------------------------------------------------"

# A. AppX Service Check
$AppxService = Get-Service -Name AppXSVC -ErrorAction SilentlyContinue
if ($null -eq $AppxService -or $AppxService.Status -ne 'Running') {
    try {
        Write-Output "[INFO] Starting AppXSVC..."
        Start-Service -Name AppXSVC
    } catch {
        Write-Output "[ERROR] Cannot start AppXSVC. Aborting."
        Stop-Transcript
        exit 1001
    }
}

# B. Process Interference Check
Write-Output "[INFO] Checking for running target processes..."
foreach ($App in $AppsToRemove) {
    $SanitizedName = $App.Replace("*", "")
    if ($SanitizedName -and (Get-Process | Where-Object { $_.ProcessName -like "*$SanitizedName*" })) {
        Write-Output "[CRITICAL] Process '$SanitizedName' is running. Exiting (1618)."
        Stop-Transcript
        exit 1618
    }
}

# --------------------------------------------------------------------------
# 3. REMOVAL LOGIC
# --------------------------------------------------------------------------
foreach ($AppName in $AppsToRemove) {
    Write-Output "`n[PROCESSING] $AppName"

    # Part A: De-provision (Future Users)
    try {
        $Provisioned = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like "$AppName*" }
        foreach ($Prov in $Provisioned) {
            Write-Output "  -> Removing Provisioned: $($Prov.PackageName)"
            Remove-AppxProvisionedPackage -Online -PackageName $Prov.PackageName -ErrorAction Stop | Out-Null
        }
    } catch {
        Write-Output "  [!] Provisioned removal skipped/failed: $($_.Exception.Message)"
    }

    # Part B: Remove Installed (Current Users)
    try {
        $Installed = Get-AppxPackage -AllUsers | Where-Object { $_.Name -like "$AppName*" }
        foreach ($Pkg in $Installed) {
            Write-Output "  -> Removing Installed: $($Pkg.Name) (All Users)"
            Remove-AppxPackage -Package $Pkg.PackageFullName -AllUsers -ErrorAction Stop | Out-Null
        }
    } catch {
        Write-Output "  [!] Installed removal skipped/failed: $($_.Exception.Message)"
    }
}

Write-Output "`n--------------------------------------------------------"
Write-Output "SCRIPT COMPLETED SUCCESSFULLY"
Write-Output "--------------------------------------------------------"

Stop-Transcript
exit 0