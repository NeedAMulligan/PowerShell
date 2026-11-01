# Ensure script is run with administrator privileges
If (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Please run this script in an elevated PowerShell session (Run as Administrator)."
    Exit
}

$ModuleName = "DellBIOSProvider"
$DriveName = "DellSmbios"
$Path = "DellSmbios:\PowerManagement"
$Attribute = "AcPwrRcvry"
$DesiredValue = "On"

# Step 1: Check and install module if missing
Write-Host "Checking for module: $ModuleName..." -ForegroundColor Cyan
if (-not (Get-Module -ListAvailable -Name $ModuleName)) {
    Write-Host "Module not found. Installing $ModuleName from PowerShell Gallery..." -ForegroundColor Yellow
    Install-Module -Name $ModuleName -Force -Scope AllUsers -ErrorAction Stop
    Write-Host "Module installed successfully." -ForegroundColor Green
} else {
    Write-Host "Module $ModuleName is already installed." -ForegroundColor Green
}

# Step 2: Import module
Write-Host "Importing module $ModuleName..." -ForegroundColor Cyan
Import-Module $ModuleName -ErrorAction Stop
*Verification:* If no errors appeared, the module is successfully imported.

# Step 3: Check and navigate to the Dell SMBIOS drive
if (-not (Get-PSDrive -Name $DriveName -ErrorAction SilentlyContinue)) {
    Write-Warning "The $DriveName drive is not available on this system (Ensure this is a Dell system with compatible BIOS/SMBIOS drivers)."
    Exit
}

Set-Location $Path
*Verification:* Your working directory is now set to `$Path`.

# Step 4: Set AC Power Recovery value
Write-Host "Setting $Attribute to $DesiredValue..." -ForegroundColor Cyan
Set-Item -Path ".\$Attribute" -Value $DesiredValue -ErrorAction Stop

# Step 5: Verify the new value
Write-Host "Verifying the updated configuration..." -ForegroundColor Cyan
$Result = Get-ItemProperty -Path ".\$Attribute"

if ($Result.CurrentValue -eq $DesiredValue) {
    Write-Host "SUCCESS: AC Power Recovery is verified and set to: $($Result.CurrentValue)" -ForegroundColor Green
} else {
    Write-Warning "VERIFICATION FAILED: Expected '$DesiredValue', but current value is '$($Result.CurrentValue)'."
}