<#
.SYNOPSIS
  Performs system preparation and schedules a restart, providing real-time user output.

.DESCRIPTION
  This script performs the following tasks:
  1. Removes the Windows Feature related to Recall using AppX and Disable-WindowsOptionalFeature.
  2. Removes specific traditional software (Dell Optimizer, Dell Pair, non-AppX Remote Desktop) silently.
  3. **Configures Dell Command Update (DCU) for automatic download/notify and enables Advanced Driver Restore, then runs updates.**
  4. Runs the Microsoft Support and Recovery Assistant (SaRA) to completely uninstall ALL versions of Microsoft Office/OneNote silently.
  5. Runs the AppX removal script to remove unnecessary Windows 11 applications.
  6. Queries the system serial number and renames the computer to 'RB-SERIALNUMBER'.
  7. Configures power buttons, display, and sleep settings to 'Do Nothing'/'Never'.
  8. Installs NuGet Provider, PSGallery, and PSWindowsUpdate module to run OS updates using -IgnoreReboot.
  9. Runs 'winget upgrade --all' to update applications, automatically accepting agreements.
  10. Logs all actions to a dynamically named file in C:\temp AND provides real-time console output.
  11. Schedules a system restart with a 5-second countdown.

.NOTES
  Requires administrative privileges to run.
  *** MODIFIED: DCU configuration settings added to enable automatic download/notify and ADR. ***

.EXITCODES
  0 - Success: All tasks completed successfully.
  1 - Failure: Could not retrieve the serial number, cannot continue with renaming.
  2 - Failure: An error occurred during the computer renaming process.
  3 - Failure: An error occurred during the power configuration process.
  4 - Failure: An error occurred during the Windows Update module or OS update process.
  5 - Failure: An error occurred during the Winget application update process.
  6 - Failure: An error occurred during the Recall feature removal.
  8 - Failure: An error occurred during the Dell/Traditional software removal.
  9 - Failure: An error occurred during the SaRA Office removal process.
  10 - Failure: An error occurred during the AppX package removal process.
  12 - Failure: An error occurred during the Dell Command Update (DCU) process.
  14 - Failure: Pre-execution log directory creation failed.
#>
$ExitCode = 0
$LogFile = "C:\temp\Rename_Power_Update_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$LogDir = Split-Path -Parent $LogFile
$NewComputerName = ""
$WingetPath = "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"

# 0. Set Execution Policy (Temporary for this Process)
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# Function to write log AND console output (Now includes Write-Host for user visibility)
Function Write-Status {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [string]$Level = "INFO" # INFO, SUCCESS, ERROR
    )
    # Log Entry Creation
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "$Timestamp - $Level - $Message"
    Add-Content -Path $LogFile -Value $LogMessage
    
    # CONSOLE OUTPUT: Write to console for user visibility
    switch ($Level) {
        "SUCCESS" { Write-Host "[OK] $Message" -ForegroundColor Green }
        "ERROR"   { Write-Host "[ERROR] $Message" -ForegroundColor Red }
        default   { Write-Host "[INFO] $Message" -ForegroundColor Cyan }
    }
}

# Ensure the log directory exists before proceeding and handle potential failure
Try {
    If (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
} Catch {
    $ExitCode = 14
    Exit $ExitCode
}

Write-Status "--- Script Start ---"
Write-Status "Execution Policy set to Bypass for current process."
Write-Status "Log file being saved to: $LogFile"
Write-Host "" # Add newline for visual separation

# ----------------------------------------------------------------------------------------------------------------------
# 0. FILE LOCATION VERIFICATION
Write-Status "SECTION 0: File Location Verification"
Write-Status "Log directory verified at '$LogDir'." -Level SUCCESS
Write-Status "Skipping ScreenConnect file check per previous request."

Write-Host ""
# ----------------------------------------------------------------------------------------------------------------------
# 1. Remove Recall/Windows Feature Experience Pack
Write-Status "SECTION 1: Removing Recall Feature"
Try {
    Write-Status "Attempting to remove the Windows Feature Experience Pack (Recall component) via AppX removal..."
    
    $PackageName = "Microsoft.Windows.FeatureExperiencePack"
    $Package = Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue
    
    if ($Package) {
        Write-Status "Found AppX Package '$PackageName'. Attempting to remove it..."
        Remove-AppxPackage -Package $Package.PackageFullName -ErrorAction Stop
        Write-Status "AppX Package removed successfully." -Level SUCCESS
    }
    
    Write-Status "Attempting to disable the 'Recall' optional feature using Disable-WindowsOptionalFeature..."
    Disable-WindowsOptionalFeature -Online -FeatureName "Recall" -Remove -NoRestart -ErrorAction SilentlyContinue | Out-Null
    Disable-WindowsOptionalFeature -Online -FeatureName "Windows-Feature-Experience-Pack" -Remove -NoRestart -ErrorAction SilentlyContinue | Out-Null

    Write-Status "Recall feature removal commands executed (NoRestart specified)." -Level SUCCESS

} Catch {
    Write-Status "ERROR during Recall feature removal: $($_.Exception.Message)" -Level ERROR
    $ExitCode = 6
}

Write-Host ""
# ----------------------------------------------------------------------------------------------------------------------
# 2. Remove Dell and Traditional Software (Excluding Office)
Write-Status "SECTION 2: Removing Dell and Traditional Software (Dell Optimizer, Dell Pair, Remote Desktop)"
Try {
    $SoftwareToRemove = @(
        "Dell Optimizer",
        "Dell Pair", 
        "Remote Desktop"
    )

    $PackagesRemovedCount = 0
    foreach ($SoftwareName in $SoftwareToRemove) {
        Write-Status "Searching for software: '$SoftwareName'..."
        $FoundSoftware = Get-Package -Name $SoftwareName -Provider Programs, MSI -ErrorAction SilentlyContinue | Select-Object -First 1

        if ($FoundSoftware) {
            Write-Status "Found '$SoftwareName'. Uninstalling silently..."
            Uninstall-Package -Name $SoftwareName -Provider $FoundSoftware.ProviderName -Force -ErrorAction Stop
            $PackagesRemovedCount++
            Write-Status "'$SoftwareName' uninstalled successfully." -Level SUCCESS
        } else {
            Write-Status "Software '$SoftwareName' not found. Skipping."
        }
    }
    Write-Status "Completed removal attempts. $PackagesRemovedCount traditional software packages were uninstalled."
} Catch {
    Write-Status "ERROR during Dell/Traditional software removal: $($_.Exception.Message)" -Level ERROR
    $ExitCode = 8
}

Write-Host ""
# ----------------------------------------------------------------------------------------------------------------------
# 3. Dell Command Update (DCU) - Configuration and Updates
Write-Status "SECTION 3: Dell Command Update (DCU) Configuration and Execution"
Try {
    $DcuPath_x86 = "C:\Program Files (x86)\Dell\CommandUpdate\dcu-cli.exe"
    $DcuPath_x64 = "C:\Program Files\Dell\CommandUpdate\dcu-cli.exe"
    $DcuPath = $null
    $RegPath = "HKLM:\SOFTWARE\Dell\CommandUpdate\Service"

    if (Test-Path $DcuPath_x64) {
        $DcuPath = $DcuPath_x64
    } elseif (Test-Path $DcuPath_x86) {
        $DcuPath = $DcuPath_x86
    }

    If ($DcuPath) {
        Write-Status "Found Dell Command Update CLI at: '$DcuPath'."
        
        # --- DCU Configuration ---
        Write-Status "Applying Dell Command Update service configuration..."

        # 1. Set to Download Updates and Notify (1)
        Write-Status "Setting update option to 'Download and Notify' (Daily check interval set to 7 days)."
        Set-ItemProperty -Path $RegPath -Name "NotificationOption" -Value 1 -Type DWORD -Force -ErrorAction Stop
        Set-ItemProperty -Path $RegPath -Name "SchedulerIntervalInDays" -Value 7 -Type DWORD -Force -ErrorAction Stop
        
        # 2. Enable Advanced Driver Restore (1)
        Write-Status "Enabling Advanced Driver Restore (ADR)."
        Set-ItemProperty -Path $RegPath -Name "EnableAdvancedDriverRestore" -Value 1 -Type DWORD -Force -ErrorAction Stop
        
        Write-Status "DCU Configuration complete." -Level SUCCESS
        
        # --- DCU Update Execution ---
        Write-Status "Starting silent update process (/applyUpdates). Will NOT force a reboot."
        & "$DcuPath" /applyUpdates -silent -outputLog "C:\temp\DCU_updates_$(Get-Date -Format 'yyyyMMdd_HHmmss').log" -ErrorAction Stop
        
        Write-Status "Dell Command Update completed successfully. Check the DCU log for required reboots." -Level SUCCESS
    } Else {
        Write-Status "Dell Command Update CLI (dcu-cli.exe) not found. Skipping Dell configuration and updates." -Level INFO
    }

} Catch {
    Write-Status "ERROR during Dell Command Update process (Configuration or Execution): $($_.Exception.Message)" -Level ERROR
    $ExitCode = 12
}

Write-Host ""
# ----------------------------------------------------------------------------------------------------------------------
# 4. Use SaRA Tool for Complete Office Uninstallation
Write-Status "SECTION 4: Complete Microsoft Office/OneNote Removal (using SaRAcmd)"
Try {
    $SaRAZipUrl = "https://aka.ms/SaRA_CommandLineVersionFiles"
    $SaRAZipPath = "C:\temp\SaRA_CommandLine.zip"
    $SaRADir = "C:\temp\SaRA_OfficeScrub"
    $SaRAExe = "$SaRADir\SaRAcmd.exe"
    
    Write-Status "Downloading SaRA Command Line Tool from $SaRAZipUrl..."
    Invoke-WebRequest -Uri $SaRAZipUrl -OutFile $SaRAZipPath -ErrorAction Stop | Out-Null
    Write-Status "Download complete. Extracting files..."
    
    Expand-Archive -Path $SaRAZipPath -DestinationPath $SaRADir -Force -ErrorAction Stop
    Write-Status "Extraction complete. Running SaRAcmd silently to remove ALL Office versions..."

    Start-Process -FilePath $SaRAExe -ArgumentList "-S OfficeScrubScenario -AcceptEula -OfficeVersion All" -Wait -NoNewWindow -ErrorAction Stop
    
    Write-Status "SaRA OfficeScrub scenario completed successfully." -Level SUCCESS

    Write-Status "Cleaning up downloaded SaRA files..."
    Remove-Item -Path $SaRADir, $SaRAZipPath -Recurse -Force -ErrorAction SilentlyContinue
    
} Catch {
    Write-Status "ERROR during SaRA Office removal process: $($_.Exception.Message)" -Level ERROR
    $ExitCode = 9
}

Write-Host ""
# ----------------------------------------------------------------------------------------------------------------------
# 5. Remove Windows 11 AppX Applications (Verbose)
Write-Status "SECTION 5: Removing Windows AppX Applications"
Try {
    $AppsToRemove = @(
        "Microsoft.WindowsFeedbackHub", "Microsoft.Copilot", "Microsoft.OutlookForWindows", "Microsoft.People",
        "Microsoft.Xbox.TCUI", "Microsoft.XboxGameCallableUI", "AD2F1837.HPEasyClean", "AD2F1837.HPQuickDrop",
        "Microsoft.BingFinance", "DellInc.DellDigitalDelivery", "DellInc.DellOptimizer", "*Disney*",
        "king.com.CandyCrushFriends", "king.com.FarmHeroesSaga", "*McAfee*", "Microsoft.MicrosoftPaymentExperience",
        "Microsoft.BingNews", "Microsoft.Copilot", "Microsoft.BingWeather", "Microsoft.GamingApp",
        "Microsoft.GetHelp", "Microsoft.Getstarted", "Microsoft.MicrosoftOfficeHub", "Microsoft.MicrosoftSolitaireCollection",
        "Microsoft.MixedReality.Portal", "Microsoft.PowerAutomateDesktop", "Microsoft.Print3D", "Microsoft.SkypeApp",
        "Microsoft.Windows.DevHome", "microsoft.windowscommunicationsapps", "Microsoft.WindowsMaps", "Microsoft.XboxApp",
        "Microsoft.XboxGameOverlay", "Microsoft.XboxGamingOverlay", "Microsoft.XboxIdentityProvider",
        "Microsoft.XboxOneSmartGlass", "Microsoft.XboxSpeechToTextOverlay", "Microsoft.ZuneMusic",
        "Microsoft.ZuneVideo", "MicrosoftCorporationII.MicrosoftFamily", "MicrosoftCorporationII.QuickAssist",
        "Microsoft.RemoteDesktop", 
        "Microsoft.GamingServices" 
    )

    Write-Status "Starting removal of specified Microsoft Store applications..." -Level INFO
    
    foreach ($AppName in $AppsToRemove) {
        Write-Status "Attempting AppX removal for: $($AppName)..."
        
        # --- Step 1: Remove from provisioned packages (for new users) ---
        try {
            Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like "$AppName*" } | ForEach-Object {
                Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction Stop
                Write-Status "  Removed provisioned package: $($_.DisplayName)" -Level SUCCESS
            }
        }
        catch {
            Write-Status "  Could not remove provisioned package for '$AppName'." -Level ERROR
        }

        # --- Step 2: Remove for all existing users ---
        try {
            Get-AppxPackage -AllUsers | Where-Object { $_.Name -like "$AppName*" } | ForEach-Object {
                Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction Stop
                Write-Status "  Removed installed package for existing users: $($_.Name)" -Level SUCCESS
            }
        }
        catch {
            Write-Status "  Could not remove installed package for '$AppName' for all users." -Level ERROR
        }
    }

    Write-Status "Application removal process completed." -Level SUCCESS

} Catch {
    Write-Status "FATAL ERROR during AppX package removal process: $($_.Exception.Message)" -Level ERROR
    $ExitCode = 10
}

Write-Host ""
# ----------------------------------------------------------------------------------------------------------------------
# 6. Get Serial Number and Define New Computer Name
Write-Status "SECTION 6: Computer Renaming (Serial Number Retrieval)"
Write-Status "Attempting to retrieve computer serial number..."
Try {
    $SerialNumber = (Get-CimInstance -ClassName Win32_BIOS).SerialNumber
    If ([string]::IsNullOrWhiteSpace($SerialNumber)) {
        Write-Status "Serial number could not be retrieved. Exiting script." -Level ERROR
        $ExitCode = 1
        Exit $ExitCode
    }
    $NewComputerName = "RB-$($SerialNumber)"
    Write-Status "Serial Number found: '$SerialNumber'. New Computer Name: '$NewComputerName'." -Level SUCCESS
} Catch {
    Write-Status "FATAL ERROR during serial number retrieval: $($_.Exception.Message)" -Level ERROR
    $ExitCode = 1
    Exit $ExitCode
}

# 7. Rename the Computer
Write-Status "SECTION 7: Computer Renaming (Apply Name)"
Write-Status "Attempting to rename computer to '$NewComputerName'..."
Try {
    If ((Get-ComputerInfo).CsName -ne $NewComputerName) {
        Rename-Computer -NewName $NewComputerName -Force
        Write-Status "Computer successfully renamed to '$NewComputerName'. A REBOOT IS REQUIRED for the rename to take effect." -Level SUCCESS
    } Else {
        Write-Status "Computer is already named '$NewComputerName'. Skipping rename." -Level INFO
    }
} Catch {
    Write-Status "ERROR during computer renaming: $($_.Exception.Message)" -Level ERROR
    $ExitCode = 2
}

Write-Host ""
# ----------------------------------------------------------------------------------------------------------------------
# 8. Configure Power Options (Active Power Scheme)
Write-Status "SECTION 8: Power Configuration"
Write-Status "Configuring power scheme settings on the ACTIVE plan..."
Try {
    $ActiveScheme = (powercfg /getactivescheme).Split(" ")[3]
    Write-Status "Active Power Scheme GUID is: $ActiveScheme."
    
    Write-Status "Setting Power Button actions to 'Do Nothing'."
    powercfg /setdcvalueindex $ActiveScheme 4f971e89-eebd-4455-a8de-9e59040e7347 7648efa3-dd9c-4e3e-b566-50f929386b87 0 | Out-Null
    powercfg /setacvalueindex $ActiveScheme 4f971e89-eebd-4455-a8de-9e59040e7347 7648efa3-dd9c-4e3e-b566-50f929386b87 0 | Out-Null

    Write-Status "Setting 'Turn off the display' to 'Never'."
    powercfg /setdcvalueindex $ActiveScheme 7516b95f-f776-4464-8c53-06167f40cc99 3c0bc021-c8a8-4e07-a815-698e7259695b 0 | Out-Null
    powercfg /setacvalueindex $ActiveScheme 7516b95f-f776-4464-8c53-06167f40cc99 3c0bc021-c8a8-4e07-a815-698e7259695b 0 | Out-Null

    Write-Status "Setting 'Put the computer to sleep' to 'Never'."
    powercfg /setdcvalueindex $ActiveScheme 238c9fa8-0aad-41ed-83f4-97be2420c8f0 29f6c1db-86da-48c5-9fdb-f2b67b178847 0 | Out-Null
    powercfg /setacvalueindex $ActiveScheme 238c9fa8-0aad-41ed-83f4-97be2420c8f0 29f6c1db-86da-48c5-9fdb-f2b67b178847 0 | Out-Null

    powercfg /S $ActiveScheme | Out-Null
    Write-Status "Power scheme configuration complete." -Level SUCCESS
} Catch {
    Write-Status "ERROR during power configuration: $($_.Exception.Message)" -Level ERROR
    $ExitCode = 3
}

Write-Host ""
# ----------------------------------------------------------------------------------------------------------------------
# 9. Download and Install Windows Update PowerShell Module and Install Updates
Write-Status "SECTION 9: Windows Update (using PSWindowsUpdate)"
Write-Status "Preparing environment for module installation (NuGet, PSGallery)..."
Try {
    Write-Status "Installing NuGet provider silently..."
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers -ErrorAction Stop | Out-Null
    Write-Status "NuGet provider installed/updated."

    If (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)) {
        Write-Status "PSGallery repository not found. Attempting to register it."
        Register-PSRepository -Name PSGallery -SourceLocation 'https://www.powershellgallery.com/api/v2/' -InstallationPolicy Trusted -ErrorAction Stop | Out-Null
        Write-Status "PSGallery repository successfully registered and trusted." -Level SUCCESS
    } Else {
        Write-Status "PSGallery repository is already registered."
    }

    Write-Status "Installing and Importing PSWindowsUpdate module using -Force..."
    Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -ErrorAction Stop | Out-Null
    Import-Module PSWindowsUpdate -ErrorAction Stop | Out-Null
    Write-Status "PSWindowsUpdate module installed and imported successfully." -Level SUCCESS

    Write-Status "Searching for available Windows and Microsoft updates (Get-WindowsUpdate)..."
    $Updates = Get-WindowsUpdate
    $UpdateCount = $Updates.Count

    If ($UpdateCount -gt 0) {
        Write-Status "Found $UpdateCount available updates. Starting installation..."

        Write-Status "Installing updates with -MicrosoftUpdate -AcceptAll, and -IgnoreReboot..."
        Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot -ErrorAction Stop
        
        Write-Status "All OS updates installed successfully." -Level SUCCESS
    } Else {
        Write-Status "No available OS updates found." -Level INFO
    }
} Catch {
    Write-Status "ERROR during PSWindowsUpdate module or installation: $($_.Exception.Message)" -Level ERROR
    $ExitCode = 4
}

Write-Host ""
# ----------------------------------------------------------------------------------------------------------------------
# 10. Run Winget Upgrade
Write-Status "SECTION 10: Application Updates (Winget)"
Try {
    If (Test-Path $WingetPath) {
        Write-Status "Running 'winget upgrade --all' to update applications. This may take some time."
        
        & $WingetPath upgrade --all --silent --accept-source-agreements --accept-package-agreements | Out-Null 2>&1
        
        If ($LASTEXITCODE -eq 0) {
            Write-Status "Winget application updates completed successfully." -Level SUCCESS
        } Else {
            Write-Status "Winget command ran, but returned a non-zero exit code: $LASTEXITCODE. Some updates may have failed." -Level ERROR
        }
    } Else {
        Write-Status "Winget executable not found at '$WingetPath'. Skipping application updates." -Level INFO
    }
} Catch {
    Write-Status "ERROR during Winget application update process: $($_.Exception.Message)" -Level ERROR
    $ExitCode = 5
}

Write-Host ""
# ----------------------------------------------------------------------------------------------------------------------
# Finalizing and Restart
Write-Status "--- Script End. Final Exit Code: $ExitCode ---"
Write-Status "Finalizing tasks. Scheduling system restart with a 5-second countdown..."
Write-Host ""

Write-Host "********************************************************************************************************************" -ForegroundColor Yellow
Write-Host "‼️ SYSTEM RESTART SCHEDULED ‼️ The computer will reboot in 5 seconds to finalize changes." -ForegroundColor Red
Write-Host "Check the log file at '$LogFile' for detailed information." -ForegroundColor Cyan
Write-Host "********************************************************************************************************************" -ForegroundColor Yellow

shutdown.exe /r /t 5 /f /c "System restart initiated by automation script for required maintenance." | Out-Null

Exit $ExitCode
