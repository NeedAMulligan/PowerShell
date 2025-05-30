# This script performs a complete uninstallation of Steam components.
# It runs silently without any console output or user interaction.
#
# WARNING: This script will permanently delete all Steam files, including your
# installed games and their save data (unless backed up separately). It will
# also remove all Steam-related settings from your registry.
#
# This script MUST be run with Administrator privileges.

# --- Step 1: Stop and Delete the Steam Client Service ---
try {
    # Stop the service if it's running
    if (Get-Service -Name "Steam Client Service" -ErrorAction SilentlyContinue) {
        Stop-Service -Name "Steam Client Service" -Force -ErrorAction Stop
    }

    # Set service to Disabled (in case it still exists but is not running)
    if (Get-Service -Name "Steam Client Service" -ErrorAction SilentlyContinue) {
        Set-Service -Name "Steam Client Service" -StartupType Disabled -ErrorAction Stop
    }

    # Delete the service
    sc.exe delete "Steam Client Service" | Out-Null
}
catch {
    # Errors are silently suppressed in this version.
    # In a production silent script, you might log errors to a file here.
}

# --- Step 2: Remove the Steam Installation Folder ---
$steamFolderPath = "C:\Program Files (x86)\Steam"
try {
    if (Test-Path $steamFolderPath) {
        Remove-Item -Path $steamFolderPath -Recurse -Force -ErrorAction Stop
    }
}
catch {
    # Errors are silently suppressed.
}

# --- Step 3: Delete Valve Registry Keys ---
$registryKeysToDelete = @(
    "HKLM:\SOFTWARE\Wow6432Node\Valve",
    "HKCU:\Software\Valve"
)

foreach ($keyPath in $registryKeysToDelete) {
    try {
        if (Test-Path $keyPath) {
            Remove-Item -Path $keyPath -Recurse -Force -ErrorAction Stop
        }
    }
    catch {
        # Errors are silently suppressed.
    }
}

# No final messages or prompts.