# This script removes specified Microsoft Store (AppX) applications for all users on the computer.
# It attempts to remove both the provisioned package (for new users) and the installed package for existing users.
#
# IMPORTANT:
# 1. Run this script with Administrator privileges.
# 2. Removing system applications can sometimes cause unexpected behavior or issues with Windows.
#    Use this script with caution and ensure you understand the implications.
# 3. Some applications might be reinstalled by Windows updates or if a new user profile is created
#    and the provisioned package was not successfully removed.
# 4. This script targets AppX packages. Traditional desktop applications (e.g., some versions of McAfee, Microsoft Teams)
#    will not be removed by this script if they are not installed as AppX packages.
# 5. This version of the script provides verbose output to the console during its execution.

# List of AppX package names (or parts of names for wildcard matching) to remove.
# These names are derived from common AppX package names found on Windows systems.
$AppsToRemove = @(
    "Microsoft.WindowsFeedbackHub",
    "Microsoft.Copilot", # Targets the Copilot appx package
    "Microsoft.OutlookForWindows",
    "Microsoft.People",
    "Microsoft.Xbox.TCUI",
    "Microsoft.XboxGameCallableUI",
    "AD2F1837.HPEasyClean",
    "AD2F1837.HPQuickDrop",
    "Microsoft.BingFinance",
    "DellInc.DellDigitalDelivery",
    "DellInc.DellOptimizer",
    "*Disney*", # Using wildcard for Disney+ or similar apps
    "king.com.CandyCrushFriends",
    "king.com.FarmHeroesSaga",
    "*McAfee*", # Using wildcard for potential McAfee UWP apps. Note: Traditional McAfee is not AppX.
    "Microsoft.MicrosoftPaymentExperience", # For Microsoft Pay
    "Microsoft.BingNews",
    "Microsoft.BingWeather",
    "Microsoft.GamingApp", # Xbox App
    "Microsoft.GetHelp",
    "Microsoft.Getstarted",
    "Microsoft.MicrosoftOfficeHub",
    "Microsoft.MicrosoftSolitaireCollection",
    "Microsoft.MixedReality.Portal",
    "Microsoft.PowerAutomateDesktop",
    "Microsoft.Print3D",
    "Microsoft.SkypeApp",
    "Microsoft.Windows.DevHome",
    "microsoft.windowscommunicationsapps", # Mail and Calendar
    "Microsoft.WindowsMaps",
    "Microsoft.XboxApp",
    "Microsoft.XboxGameOverlay",
    "Microsoft.XboxGamingOverlay",
    "Microsoft.XboxIdentityProvider",
    "Microsoft.XboxOneSmartGlass",
    "Microsoft.XboxSpeechToTextOverlay",
    "Microsoft.ZuneMusic", # Groove Music
    "Microsoft.ZuneVideo", # Movies & TV
    "MicrosoftCorporationII.MicrosoftFamily",
    "MicrosoftCorporationII.QuickAssist"
)

Write-Host "Starting removal of specified Microsoft Store applications..." -ForegroundColor Cyan

foreach ($AppName in $AppsToRemove) {
    Write-Host "`nAttempting to remove application: $($AppName)..." -ForegroundColor Yellow

    # --- Step 1: Remove from provisioned packages (for new users) ---
    # This prevents the app from being installed for new user profiles.
    # It also removes it for existing users if it was provisioned.
    try {
        Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like "$AppName*" } | ForEach-Object {
            Write-Host "  Found provisioned package: $($_.PackageName). Attempting to remove..." -ForegroundColor DarkYellow
            Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction Stop
            Write-Host "  Successfully removed provisioned package: $($_.PackageName)" -ForegroundColor Green
        }
    }
    catch {
        Write-Warning "  Could not remove provisioned package for '$AppName'. Error: $($_.Exception.Message)"
    }

    # --- Step 2: Remove for all existing users ---
    # This ensures the app is removed from currently existing user profiles.
    try {
        Get-AppxPackage -AllUsers | Where-Object { $_.Name -like "$AppName*" } | ForEach-Object {
            $UserSID = $_.PackageUserInformation.UserSID
            $PackageFullName = $_.PackageFullName
            $PackageName = $_.Name

            # Get the username associated with the SID for better logging
            try {
                $UserName = (New-Object System.Security.Principal.SecurityIdentifier($UserSID)).Translate([System.Security.Principal.NTAccount]).Value
            }
            catch {
                $UserName = "Unknown User (SID: $UserSID)"
            }

            Write-Host "  Found installed package '$PackageName' for user '$UserName'. Attempting to remove..." -ForegroundColor DarkYellow
            Remove-AppxPackage -Package $PackageFullName -AllUsers -ErrorAction Stop
            Write-Host "  Successfully removed package '$PackageName' for user '$UserName'" -ForegroundColor Green
        }
    }
    catch {
        Write-Warning "  Could not remove installed package for '$AppName' for all users. Error: $($_.Exception.Message)"
    }
}

Write-Host "`nApplication removal process completed." -ForegroundColor Cyan
