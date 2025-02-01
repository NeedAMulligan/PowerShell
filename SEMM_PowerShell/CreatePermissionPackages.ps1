#
#    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
#    AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
#    IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
#    ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
#    LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
#    CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
#    SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
#    INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
#    CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
#    ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
#    THE POSSIBILITY OF SUCH DAMAGE.
#
#    Copyright (C) Microsoft Corporation. All Rights Reserved.
#
# CreatePermissionPackage.ps1
#
# PURPOSE:
#  Demonstrates how to create a permission package.
#
# RUNS ON:
#  IT Administrator workstation (does not need to be a Surface device)
#
# PREREQUISITES:
#  1) IT Adminstrator workstation has installed the SurfaceUefiManagerSetup.msi
#  2) Ownership Certificate signing key has been generated and is accessible
#
# REMARKS:
#  Every UEFI setting has a set of permission flags which define who is allowed
#  to modify the setting.
#  You must set these flags to lock down the device settings.
#  This only needs to be done once so we recommend you do this at the same time
#  you apply the ownership package.
#
#  The identities are:
#   Signer Owner = The enterprise owner of the device
#   Local = Local user. This represents the identity of the user when using the UEFI boot menu.
#   Signer User, User 1, User 2 = Reserved for future use.
$WorkingDirPath = split-path -parent $MyInvocation.MyCommand.Definition
$packageRoot = $WorkingDirPath
$certName = "TestUefiV2.pfx"

if (!(Test-Path $packageRoot)) {
    Write-Host -ForegroundColor Yellow "!!!"
    Write-Host -ForegroundColor Yellow "You must place your .PKG configuration files in " $packageRoot
    Write-Host -ForegroundColor Yellow "!!!"
    Exit
}

$privateOwnerKey = Join-Path -Path $packageRoot -ChildPath $certName

# If your PFX has a password
$password = "1234"

if (!(Test-Path $privateOwnerKey)) {
    Write-Host -ForegroundColor Yellow "You must manually copy your signing key to " $privateOwnerKey
    Write-Host -ForegroundColor Yellow "!!! Make sure you have saved a copy and do not lose this file !!!"
    Exit
}

# Load() is the recommended way to load the assembly, but it requires knowing the exact version
# [System.Reflection.Assembly]::LoadWithPartialName("SurfaceUefiManager")
[System.Reflection.Assembly]::Load("SurfaceUefiManager, Version=2.9.136.0, Culture=neutral, PublicKeyToken=fc3210b1ec5c11d4")

# You can use the UefiManager to detect the local device version
$Device = [Microsoft.Surface.UefiManager]::CreateFromLocalDevice()
$uefi = $Device
Write-Host "Manufacturer: " $uefi.Manufacturer
Write-Host "SystemFamily: " $uefi.SystemFamily
Write-Host "Model: " $uefi.Model
Write-Host "UEFI Version: " $uefi.UefiVersion
Write-Host ""

# Must run on a Surface device
if ($uefi.SystemFamily -ne "Surface") {
  Write-Host -ForegroundColor Yellow "ERROR: This script only works for Microsoft Surface devices"
  Exit -1
}

# Older versions of UEFI may not support SEMM.
# If that is the case then you will not have a V2 UEFI object returned.
if ($uefi.ConfigurationMechanism -ne [Microsoft.Surface.IUefiConfiguration+ConfigurationMechanismEnum]::V2) {
    Write-Host -ForegroundColor Yellow "Unsupported device: You may need to update to a newer UEFI firmware version."
    Exit -1
}

# The UEFI manager class knows about all currently supported Surface devices.
$uefiManager = New-Object -TypeName Microsoft.Surface.UefiManager
$uefiManager.LoadKnownUefiConfigurations()

# The permission package is dependent on the specific device and even UEFI version.
# However:
#  1) The UEFI will safely ignore settings IDs that it does not recognize
#  2) Newer versions of UEFI generally add new settings
#  3) IDs have a consistent meaning across all Surface devices
#
# So get the latest versions for each device family.
$surfaceDevices = @{}
foreach ($uefi in $uefiManager.SurfaceUefiConfigurations) {
    # This version of SEMM is V2 so ignore other SEMM versions.
    if ($uefi.ConfigurationMechanism -eq [Microsoft.Surface.IUefiConfiguration+ConfigurationMechanismEnum]::V2) {
        if (-not $surfaceDevices.ContainsKey($uefi.SurfaceUefiFamily)) {
            $surfaceDevices.Add($uefi.SurfaceUefiFamily, $uefi)
        } else {
            $oldUefi = $surfaceDevices.Values[$uefi.SurfaceUefiFamily]
            if ($uefi.SurfaceUefiSettingsVersion -gt $oldUefi.SurfaceUefiSettingsVersion) {
                $surfaceDevices.Values[$uefi.SurfaceUefiFamily] = $uefi
            }
        }
    }
}

# The Lowest Supported Version (LSV) is a 64-bit integer assigned to a permission or settings package.
# (There are two independent LSV values in UEFI: One for permissions, one for settings)
# Whenever a package is sent to UEFI, the UEFI boot process will only allow packages
# with LSV equal to or greater than the current package.
# This is a security feature to prevent a replay attack where somebody tries to re-apply an older package.
#
# The algorithm used by the UEFI Configurator GUI tool is to calculate seconds since the year 2000.
# We will use the same algorithm here.
$year2000 = New-Object -TypeName "System.DateTime" -ArgumentList 2000,1,1
$year2000Utc = $year2000.ToUniversalTime()

$timeDiff = [System.DateTime]::UtcNow - $year2000Utc
$lsv = [System.Convert]::ToInt64($timeDiff.TotalSeconds)

# Configure Permissions
foreach ($uefiV2 IN $surfaceDevices.Values) {
    if ($uefiV2.SurfaceUefiFamily -eq $Device.Model) {
        Write-Host "Configuring permissions"
        Write-Host $Device.Model
        Write-Host "======================="

        # Here we define which "identities" will be allowed to modify which settings
        #   PermissionSignerOwner = The primary SEMM enterprise owner identity
        #   PermissionLocal = The user when booting to the UEFI pre-boot GUI
        #   PermissionSignerUser, PermissionSignerUser1, PermissionSignerUser2 =
        #     Additional user identities created so that the signer owner
        #     can delegate permission control for some settings.
        $ownerOnly = [Microsoft.Surface.IUefiSetting]::PermissionSignerOwner
        $ownerAndLocalUser = ([Microsoft.Surface.IUefiSetting]::PermissionSignerOwner -bor [Microsoft.Surface.IUefiSetting]::PermissionLocal)

        # Make all permissions owner only by default
        foreach ($setting IN $uefiV2.Settings.Values) {
            $setting.ConfiguredPermissionFlags = $ownerOnly
        }

        # Allow the local user to change their own password and enable/disable the TPM
        # For demonstration purposes, we show how to do this by name and ID (ID is preferred)
        $uefiV2.SettingsById[501].ConfiguredPermissionFlags = $ownerAndLocalUser
        $uefiV2.Settings["Trusted Platform Module (TPM)"].ConfiguredPermissionFlags = $ownerAndLocalUser

        Write-Host ""

        # Create a unique package name based on family and LSV.
        # We will choose a name that can be parsed by later scripts.
        $packageName = $uefiV2.SurfaceUefiFamily + "^Permissions^" + $lsv + ".pkg"
        $fullPackageName = Join-Path -Path $packageRoot -ChildPath $packageName

        # Build and sign the Permission package then save it to a file.
        $permissionPackageStream =  $uefiV2.BuildAndSignPermissionPackage($privateOwnerKey, $password, "", $null, $lsv)
        $permissionPackage = New-Object System.IO.Filestream($fullPackageName, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
        $permissionPackageStream.CopyTo($permissionPackage)
        $permissionPackage.Close()
    }
}

# The above packages must now be delivered to the target device and applied
