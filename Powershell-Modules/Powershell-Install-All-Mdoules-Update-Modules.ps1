# Requires running as an administrator
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "This script must be run with administrator privileges to install modules for all users."
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-File", "`"$($MyInvocation.MyCommand.Path)`""
    exit
}

# Define the modules to install and update
$modulesToInstall = @(
    "MicrosoftTeams",
    "NuGet",
    "PackageManagement",
    "PowerShellGet",
    "Microsoft.Online.SharePoint.PowerShell",
    "Microsoft.WinGet.Client",
    "Microsoft.Graph"
)

$installFailed = $false

Write-Host "Starting module installation and update process..."

# Fix: Set the PSGallery repository to trusted to avoid prompts
try {
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop
    Write-Host "PSGallery repository is now trusted."
}
catch {
    Write-Error "Failed to set PSGallery repository to trusted. Error: $_"
    $installFailed = $true
}

# Fix: Install NuGet package provider
Write-Host "Installing NuGet package provider..."
try {
    Install-PackageProvider -Name NuGet -Force -Confirm:$false -ErrorAction Stop
    Write-Host "Successfully installed NuGet package provider."
}
catch {
    Write-Error "Failed to install NuGet package provider. Error: $_"
    $installFailed = $true
}

# Fix: Install Windows Feature
Write-Host "Installing Windows Feature: RSAT-AD-PowerShell..."
try {
    Install-WindowsFeature -Name RSAT-AD-PowerShell -IncludeAllSubFeature -ErrorAction Stop
    Write-Host "Successfully installed RSAT-AD-PowerShell."
}
catch {
    Write-Error "Failed to install RSAT-AD-PowerShell. Error: $_"
    $installFailed = $true
}

# Fix: Loop through and install/update each module
foreach ($module in $modulesToInstall) {
    Write-Host "Checking for module: $module..."

    if (Get-InstalledModule -Name $module -ErrorAction SilentlyContinue) {
        Write-Host "Module '$module' is already installed. Checking for updates..."
        try {
            Update-Module -Name $module -Force -AcceptLicense -Confirm:$false -ErrorAction Stop
            Write-Host "Successfully updated module '$module'."
        }
        catch {
            Write-Error "Failed to update module '$module'. Error: $_"
            $installFailed = $true
        }
    }
    else {
        Write-Host "Module '$module' not found. Installing..."
        try {
            Install-Module -Name $module -Scope AllUsers -Force -AcceptLicense -AllowClobber -Confirm:$false -ErrorAction Stop
            Write-Host "Successfully installed module '$module'."
        }
        catch {
            Write-Error "Failed to install module '$module'. Error: $_"
            $installFailed = $true
        }
    }
}

# Final verification
if (-not $installFailed) {
    Write-Host "All specified modules and features have been processed successfully. ✨"
    Write-Host "Listing all installed modules for verification:"
    Get-Module -ListAvailable
} else {
    Write-Warning "Some installations or updates failed. Please review the errors above."
}
