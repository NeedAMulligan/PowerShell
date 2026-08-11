#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Configures an HP computer to automatically power on after AC power is restored.

.DESCRIPTION
    - Verifies the computer is manufactured by HP.
    - Ensures a PowerShellGet version supporting -AcceptLicense is available.
    - Installs HP Client Management Script Library (HPCMSL) if required.
    - Imports HPCMSL.
    - Finds the HP BIOS setting "After Power Loss".
    - Sets it to "Power On".
    - Verifies the change.

.NOTES
    Intended for local execution or deployment through ManageEngine UEMS.
    Target computers are expected to have no BIOS setup password.
#>

$ErrorActionPreference = "Stop"

$ModuleName       = "HPCMSL"
$BIOSSettingName  = "After Power Loss"
$DesiredValue     = "Power On"


function Write-Log {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR")]
        [string]$Level = "INFO"
    )

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    Write-Host "[$Timestamp] [$Level] $Message"
}


# ============================================================
# Verify HP Hardware
# ============================================================

try {
    Write-Log "Checking computer manufacturer..."

    $ComputerSystem = Get-CimInstance `
        -ClassName Win32_ComputerSystem `
        -ErrorAction Stop

    Write-Log "Manufacturer: $($ComputerSystem.Manufacturer)"
    Write-Log "Model: $($ComputerSystem.Model)"

    if ($ComputerSystem.Manufacturer -notmatch "HP|Hewlett-Packard") {
        Write-Log "This device is not manufactured by HP. No changes will be made." "ERROR"
        exit 1
    }

    Write-Log "HP hardware detected." "SUCCESS"
}
catch {
    Write-Log "Unable to determine computer manufacturer: $($_.Exception.Message)" "ERROR"
    exit 1
}


# ============================================================
# Enable TLS 1.2
# ============================================================

try {
    Write-Log "Enabling TLS 1.2..."

    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor
        [Net.SecurityProtocolType]::Tls12

    Write-Log "TLS 1.2 enabled." "SUCCESS"
}
catch {
    Write-Log "Unable to enable TLS 1.2: $($_.Exception.Message)" "ERROR"
    exit 1
}


# ============================================================
# Ensure NuGet Package Provider
# ============================================================

try {
    $NuGetProvider = Get-PackageProvider `
        -Name NuGet `
        -ErrorAction SilentlyContinue

    if (-not $NuGetProvider) {

        Write-Log "NuGet package provider is not installed. Installing..."

        Install-PackageProvider `
            -Name NuGet `
            -MinimumVersion 2.8.5.201 `
            -Force `
            -ErrorAction Stop |
            Out-Null

        Write-Log "NuGet package provider installed." "SUCCESS"
    }
    else {
        Write-Log "NuGet package provider is already installed."
    }
}
catch {
    Write-Log "Failed to install NuGet provider: $($_.Exception.Message)" "ERROR"
    exit 1
}


# ============================================================
# Ensure PSGallery
# ============================================================

try {
    $PSGallery = Get-PSRepository `
        -Name PSGallery `
        -ErrorAction SilentlyContinue

    if (-not $PSGallery) {

        Write-Log "PSGallery is not registered. Restoring default repositories..."

        Register-PSRepository `
            -Default `
            -ErrorAction Stop

        $PSGallery = Get-PSRepository `
            -Name PSGallery `
            -ErrorAction Stop
    }


    if ($PSGallery.InstallationPolicy -ne "Trusted") {

        Write-Log "Setting PSGallery to Trusted..."

        Set-PSRepository `
            -Name PSGallery `
            -InstallationPolicy Trusted `
            -ErrorAction Stop
    }

    Write-Log "PSGallery is available." "SUCCESS"
}
catch {
    Write-Log "Unable to configure PSGallery: $($_.Exception.Message)" "ERROR"
    exit 1
}


# ============================================================
# Ensure PowerShellGet Supports -AcceptLicense
# ============================================================

try {
    Write-Log "Checking PowerShellGet compatibility..."

    $InstallModuleCommand = Get-Command `
        Install-Module `
        -ErrorAction Stop

    $SupportsAcceptLicense =
        $InstallModuleCommand.Parameters.ContainsKey("AcceptLicense")


    if (-not $SupportsAcceptLicense) {

        Write-Log "Current PowerShellGet does not support -AcceptLicense." "WARNING"
        Write-Log "Upgrading PowerShellGet..."

        #
        # The older Install-Module cmdlet can install PowerShellGet itself
        # without using -AcceptLicense.
        #
        Install-Module `
            -Name PowerShellGet `
            -Repository PSGallery `
            -Scope AllUsers `
            -Force `
            -AllowClobber `
            -ErrorAction Stop


        Write-Log "New PowerShellGet version installed." "SUCCESS"


        # ----------------------------------------------------
        # Remove currently loaded old PowerShellGet
        # ----------------------------------------------------

        Remove-Module PowerShellGet `
            -Force `
            -ErrorAction SilentlyContinue


        # ----------------------------------------------------
        # Locate newest installed PowerShellGet
        # ----------------------------------------------------

        $NewestPowerShellGet = Get-Module `
            -ListAvailable `
            -Name PowerShellGet |
            Sort-Object Version -Descending |
            Select-Object -First 1


        if (-not $NewestPowerShellGet) {
            throw "PowerShellGet was installed but cannot be located."
        }


        Write-Log "Loading PowerShellGet version $($NewestPowerShellGet.Version)..."

        Import-Module `
            $NewestPowerShellGet.Path `
            -Force `
            -ErrorAction Stop


        # ----------------------------------------------------
        # Verify -AcceptLicense is now available
        # ----------------------------------------------------

        $InstallModuleCommand = Get-Command `
            Install-Module `
            -ErrorAction Stop

        $SupportsAcceptLicense =
            $InstallModuleCommand.Parameters.ContainsKey("AcceptLicense")


        if (-not $SupportsAcceptLicense) {
            throw "PowerShellGet was upgraded, but Install-Module still does not support -AcceptLicense."
        }


        Write-Log "PowerShellGet now supports -AcceptLicense." "SUCCESS"
    }
    else {

        $LoadedPowerShellGet = Get-Module PowerShellGet |
            Sort-Object Version -Descending |
            Select-Object -First 1

        if ($LoadedPowerShellGet) {
            Write-Log "PowerShellGet version $($LoadedPowerShellGet.Version) supports -AcceptLicense." "SUCCESS"
        }
        else {
            Write-Log "Current Install-Module supports -AcceptLicense." "SUCCESS"
        }
    }
}
catch {
    Write-Log "Unable to prepare PowerShellGet: $($_.Exception.Message)" "ERROR"
    exit 1
}


# ============================================================
# Check / Install HPCMSL
# ============================================================

try {
    Write-Log "Checking whether HPCMSL is installed..."

    $InstalledModule = Get-Module `
        -ListAvailable `
        -Name $ModuleName |
        Sort-Object Version -Descending |
        Select-Object -First 1


    if (-not $InstalledModule) {

        Write-Log "HPCMSL is not installed." "WARNING"
        Write-Log "Installing HPCMSL from PowerShell Gallery..."


        #
        # -AcceptLicense is REQUIRED because current HPCMSL
        # dependencies such as HP.Private require license acceptance.
        #
        Install-Module `
            -Name $ModuleName `
            -Repository PSGallery `
            -Scope AllUsers `
            -Force `
            -AllowClobber `
            -AcceptLicense `
            -ErrorAction Stop


        $InstalledModule = Get-Module `
            -ListAvailable `
            -Name $ModuleName |
            Sort-Object Version -Descending |
            Select-Object -First 1


        if (-not $InstalledModule) {
            throw "HPCMSL installation completed, but the module cannot be found."
        }


        Write-Log "HPCMSL version $($InstalledModule.Version) installed successfully." "SUCCESS"
    }
    else {

        Write-Log "HPCMSL version $($InstalledModule.Version) is already installed." "SUCCESS"
    }
}
catch {
    Write-Log "Failed to install HPCMSL: $($_.Exception.Message)" "ERROR"
    exit 1
}


# ============================================================
# Import HPCMSL
# ============================================================

try {
    Write-Log "Importing HPCMSL..."

    Import-Module `
        $ModuleName `
        -Force `
        -ErrorAction Stop


    $RequiredCommands = @(
        "Get-HPBIOSSettingsList",
        "Get-HPBIOSSettingValue",
        "Set-HPBIOSSettingValue"
    )


    foreach ($Command in $RequiredCommands) {

        if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
            throw "Required HPCMSL command '$Command' is unavailable."
        }
    }


    Write-Log "HPCMSL imported successfully." "SUCCESS"
}
catch {
    Write-Log "Failed to import HPCMSL: $($_.Exception.Message)" "ERROR"
    exit 1
}


# ============================================================
# Locate "After Power Loss"
# ============================================================

try {
    Write-Log "Searching for BIOS setting '$BIOSSettingName'..."

    $BIOSSettings = Get-HPBIOSSettingsList `
        -ErrorAction Stop


    $PowerLossSetting = $BIOSSettings |
        Where-Object {
            $_.Name -eq $BIOSSettingName
        } |
        Select-Object -First 1


    if (-not $PowerLossSetting) {

        Write-Log "Exact BIOS setting '$BIOSSettingName' was not found." "WARNING"

        $PossibleSettings = $BIOSSettings |
            Where-Object {
                $_.Name -match "Power Loss|AC Power"
            }


        if ($PossibleSettings) {

            Write-Log "Possible related BIOS settings:" "WARNING"

            foreach ($Setting in $PossibleSettings) {
                Write-Log "$($Setting.Name) = $($Setting.Value)" "WARNING"
            }
        }


        Write-Log "Unable to safely determine the correct BIOS setting. No BIOS changes were made." "ERROR"
        exit 1
    }


    $ActualSettingName = $PowerLossSetting.Name

    Write-Log "Found BIOS setting '$ActualSettingName'." "SUCCESS"
}
catch {
    Write-Log "Unable to retrieve HP BIOS settings: $($_.Exception.Message)" "ERROR"
    exit 1
}


# ============================================================
# Read Current Value
# ============================================================

try {
    $CurrentValue = Get-HPBIOSSettingValue `
        -Name $ActualSettingName `
        -ErrorAction Stop


    if (
        $CurrentValue -isnot [string] -and
        $null -ne $CurrentValue.Value
    ) {
        $CurrentValue = $CurrentValue.Value
    }


    $CurrentValue = "$CurrentValue".Trim()


    Write-Log "Current value: '$CurrentValue'"
    Write-Log "Desired value: '$DesiredValue'"
}
catch {
    Write-Log "Unable to read BIOS setting '$ActualSettingName': $($_.Exception.Message)" "ERROR"
    exit 1
}


# ============================================================
# Already Correct
# ============================================================

if ($CurrentValue -eq $DesiredValue) {

    Write-Log "'$ActualSettingName' is already set to '$DesiredValue'." "SUCCESS"
    Write-Log "No BIOS changes are required." "SUCCESS"

    exit 0
}


# ============================================================
# Set BIOS Value
# ============================================================

try {
    Write-Log "Changing '$ActualSettingName' from '$CurrentValue' to '$DesiredValue'..."


    Set-HPBIOSSettingValue `
        -Name $ActualSettingName `
        -Value $DesiredValue `
        -ErrorAction Stop


    Write-Log "BIOS setting command completed successfully." "SUCCESS"
}
catch {
    Write-Log "Failed to change '$ActualSettingName': $($_.Exception.Message)" "ERROR"
    exit 1
}


# ============================================================
# Verify BIOS Value
# ============================================================

try {
    Write-Log "Verifying BIOS setting..."

    Start-Sleep -Seconds 2


    $VerifiedValue = Get-HPBIOSSettingValue `
        -Name $ActualSettingName `
        -ErrorAction Stop


    if (
        $VerifiedValue -isnot [string] -and
        $null -ne $VerifiedValue.Value
    ) {
        $VerifiedValue = $VerifiedValue.Value
    }


    $VerifiedValue = "$VerifiedValue".Trim()


    Write-Log "BIOS reports '$ActualSettingName' = '$VerifiedValue'."


    if ($VerifiedValue -ne $DesiredValue) {

        Write-Log "Verification failed." "ERROR"
        Write-Log "Expected: '$DesiredValue'" "ERROR"
        Write-Log "Actual:   '$VerifiedValue'" "ERROR"

        exit 1
    }


    Write-Log "============================================================" "SUCCESS"
    Write-Log "HP BIOS configuration completed successfully." "SUCCESS"
    Write-Log "$ActualSettingName = $VerifiedValue" "SUCCESS"
    Write-Log "Computer will automatically power on when AC power returns." "SUCCESS"
    Write-Log "============================================================" "SUCCESS"

    exit 0
}
catch {
    Write-Log "Unable to verify BIOS setting: $($_.Exception.Message)" "ERROR"
    exit 1
}

