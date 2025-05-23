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
# 5. This version of the script runs silently, meaning no output will be displayed in the console
#    during its execution. Errors will be suppressed.

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

# Loop through each app and attempt to remove it silently
foreach ($AppName in $AppsToRemove) {
    # --- Step 1: Remove from provisioned packages (for new users) ---
    # This prevents the app from being installed for new user profiles.
    # It also removes it for existing users if it was provisioned.
    try {
        Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like "$AppName*" } | ForEach-Object {
            Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null
        }
    }
    catch {
        # Suppress any errors during provisioned package removal
        $_ | Out-Null
    }

    # --- Step 2: Remove for all existing users ---
    # This ensures the app is removed from currently existing user profiles.
    try {
        Get-AppxPackage -AllUsers | Where-Object { $_.Name -like "$AppName*" } | ForEach-Object {
            $PackageFullName = $_.PackageFullName
            Remove-AppxPackage -Package $PackageFullName -AllUsers -ErrorAction SilentlyContinue | Out-Null
        }
    }
    catch {
        # Suppress any errors during installed package removal
        $_ | Out-Null
    }
}
