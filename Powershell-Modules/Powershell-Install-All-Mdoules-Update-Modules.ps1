# Requires running as an administrator to install features and modules for all users
# Check if running as administrator
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "This script must be run with administrator privileges to install modules for all users."
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-File", "`"$($MyInvocation.MyCommand.Path)`""
    exit
}

# Define the modules to install and update
# RSAT-AD-PowerShell is a Windows feature and is handled separately
$modulesToInstall = @(
    "MicrosoftTeams",
    "NuGet",
    "PackageManagement",
    "PowerShellGet",
    "Microsoft.Online.SharePoint.PowerShell",
    "Microsoft.WinGet.Client",
    "Microsoft.Graph"
)

# A variable to track if any module installation failed
$installFailed = $false

Write-Host "Starting module installation process..."

# Install the Windows Feature
Write-Host "Installing Windows Feature: RSAT-AD-PowerShell..."
try {
    Install-WindowsFeature -Name RSAT-AD-PowerShell -IncludeAllSubFeature -ErrorAction Stop
    Write-Host "Successfully installed RSAT-AD-PowerShell."
}
catch {
    Write-Error "Failed to install RSAT-AD-PowerShell. Error: $_"
    $installFailed = $true
}

# Install NuGet Package Provider first, as it's required for some modules
Write-Host "Installing NuGet package provider..."
try {
    Install-PackageProvider -Name NuGet -Force -Confirm:$false -ErrorAction Stop
    Write-Host "Successfully installed NuGet package provider."
}
catch {
    Write-Error "Failed to install NuGet package provider. Error: $_"
    $installFailed = $true
}

# Loop through and install each module
foreach ($module in $modulesToInstall) {
    Write-Host "Installing module: $module..."
    try {
        # Use -Force and -AcceptLicense to suppress prompts
        Install-Module -Name $module -Scope AllUsers -Force -AcceptLicense -AllowClobber -Confirm:$false -ErrorAction Stop
        Write-Host "Successfully installed $module."
    }
    catch {
        Write-Error "Failed to install module $module. Error: $_"
        $installFailed = $true
    }
}

# Only proceed with updates if all installations were successful
if (-not $installFailed) {
    ---
    
    ## Updating All Modules for All Users
    
    Write-Host "All installations completed successfully. Starting the update process..."
    
    # Loop through and update each installed module for all users
    foreach ($module in $modulesToInstall) {
        Write-Host "Updating module: $module..."
        try {
            Update-Module -Name $module -Force -Confirm:$false -ErrorAction Stop
            Write-Host "Successfully updated $module."
        }
        catch {
            Write-Error "Failed to update module $module. Error: $_"
            $installFailed = $true
        }
    }

    if (-not $installFailed) {
        Write-Host "All modules and the Windows feature have been successfully installed and updated. ✨"
    } else {
        Write-Warning "Some modules failed to update. Please review the errors above."
    }

} else {
    Write-Warning "Module installations failed. The update process was not started. Please review the errors above."
}
