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
# ApplyProvisioningPackages.ps1
#
# PURPOSE:
#  Demonstrates how to apply the owner and permission packages.
#
# RUNS ON:
#  Surface device you want to apply permissions to.
#
# PREREQUISITES:
#  1) Run with administrator privileges
#  2) Surface Device has installed the SurfaceUefiManagerSetup.msi
#  3) Package was generated via CreateSettingsPackage.ps1 or similar
#
# REMARKS:
#  There are three types of UEFI SEMM packages: Owner, Permissions, Settings
#
#  The user scenario demonstrated here will set the Owner and Permissions at one time.
#  This would be appropriate in the case that the Settings you want to apply change frequently
#  but ownership and permissions do not.
#
#  It is possible to set all three packages at one time and then they would be
#  applied in the correct order by the UEFI boot process: Owner, Permissions, Settings
$WorkingDirPath = split-path -parent $MyInvocation.MyCommand.Definition
$demoRoot = $WorkingDirPath
$certName = "TestUefiV2.pfx"

$certNameOnly = [System.IO.Path]::GetFileNameWithoutExtension($certName)
$ProvisioningPackage = $certNameOnly + "ProvisioningPackage.pkg"

if (-not (Test-Path $demoRoot))  { New-Item -ItemType Directory -Force -Path $demoRoot }

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

# In this demo we assume that there may be many packages in the directory.
# The logic here will find the packages with the greatest LSV for your family of device.
# How you handle this in your environment is up to you.
$searchPattern =  $Device.Model + "^Permissions^*.pkg"
$fileEntries = [IO.Directory]::GetFiles($demoRoot, $searchPattern)
$maxName = ""
$permissionsFileName = ""
foreach($fileName in $fileEntries) 
{
    $nameOnly = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
    if ($nameOnly -gt $maxName) {
        $permissionsFileName = $fileName
        $maxName = $nameOnly
    }
}

if ($permissionsFileName -ne "") {
    # We found a valid package for this device
    # Every time you try to update a UEFI package that package generates a unique session ID.
    # Here we save that ID in local files can be checked after reboot to see if
    # the UEFI settings session ID matches the most recent one you tried to update.

    # The owner package is the same for all V2 devices
    $ownerFileName = Join-Path -Path $demoRoot -ChildPath $ProvisioningPackage
    $ownerPackageStream = New-Object System.IO.Filestream($ownerFileName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read)
    $sessionIdValue = $uefi.ApplySignerProvisioningPackage($ownerPackageStream)

    $ownerSessionIdFile = Join-Path -Path $demoRoot -ChildPath "OwnerSessionId.txt"
    $writer = New-Object System.IO.StreamWriter($ownerSessionIdFile)
    $writer.Write($sessionIdValue)
    $writer.Close()

    # Apply the permissions package based on device file
    $permissionPackageStream = New-Object System.IO.Filestream($permissionsFileName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read)
    $sessionIdValue = $uefi.ApplyPermissionPackage($permissionPackageStream)

    $permissionSessionIdFile = Join-Path -Path $demoRoot -ChildPath "PermissionSessionId.txt"
    $writer = New-Object System.IO.StreamWriter($permissionSessionIdFile)
    $writer.Write($sessionIdValue)
    $writer.Close()
}

# A reboot is required to apply the packages.
# The user will need to enter the last two characters of the thumbprint.