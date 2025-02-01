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
# CreateOwnerPackage.ps1
#
# PURPOSE:
#  Creates the signer provisioning (aka "owner") package and a universal reset package.
#
# RUNS ON:
#  IT Administrator workstation (does not need to be a Surface device)
#
# PREREQUISITES:
#  1) IT Adminstrator workstation has installed the SurfaceUefiManagerSetup.msi
#  2) Ownership Certificate signing key has been generated and is accessible
#
# WARNING:
#  We recommend that you save the PFX file in a safe location.
#  Once you apply a signer provisioning package you will not be able
#  to clear it without the PFX file that you used.
#  There is no way for you to recover your Surface device if you lose this PFX file!
#
#  The certificate in the PFX file may expire depending on how you created it.
#  When it does it will be difficult to generate reset packages.
#  We suggest you generate a universal (for your organization) reset package
#  and save it is a private and secure location in case you need it in the future.

$WorkingDirPath = split-path -parent $MyInvocation.MyCommand.Definition
$packageRoot = $WorkingDirPath
$certName = "TestUefiV2.pfx"

$certNameOnly = [System.IO.Path]::GetFileNameWithoutExtension($certName)
$ProvisioningPackage = $certNameOnly + "ProvisioningPackage.pkg"
$ResetPackage = $certNameOnly + "ResetPackage.pkg"

if (!(Test-Path $packageRoot)) {
    Write-Host -ForegroundColor Yellow "!!!"
    Write-Host -ForegroundColor Yellow "You must place your .PKG configuration files in " $packageRoot
    Write-Host -ForegroundColor Yellow "!!!"
    Exit
}

$privateOwnerKey = Join-Path -Path $packageRoot -ChildPath $certName
$ownerPackageName = Join-Path -Path $packageRoot -ChildPath $ProvisioningPackage
$resetPackageName = Join-Path -Path $packageRoot -ChildPath $ResetPackage

# If your PFX file requires a password then it can be set here, otherwise use a blank string.
$password = "1234"

if (!(Test-Path $privateOwnerKey)) {
    Write-Host -ForegroundColor Yellow "You must manually copy your signing key to " $privateOwnerKey
    Write-Host -ForegroundColor Yellow "!!! Make sure you have saved a copy and do not lose this file !!!"
    Exit
}

# Delete previous packages
if (Test-Path $ownerPackageName) {
    Remove-Item -Path $ownerPackageName
}

# Delete previous reset package
if (Test-Path $resetPackageName) {
    Remove-Item -Path $resetPackageName
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

# The signer provisioning package is independent of the family and BIOS version,
# as long as it uses the "V2" configuation mechanism for SEMM.
# Search for any appropriate UEFI and use it.
$uefiV2 = $null
foreach ($uefi in $uefiManager.SurfaceUefiConfigurations) {
    if ($uefi.ConfigurationMechanism -eq [Microsoft.Surface.IUefiConfiguration+ConfigurationMechanismEnum]::V2) {
        $uefiV2 = $uefi
        break
    }
}

# Create a signed provisioning package.
# This assumes that the current owner is nobody.
# It can also be this owner in which case this package is redundant.
$identity = [Microsoft.Surface.IUefiConfiguration+Identity]::SignerOwner
$stream = $uefiV2.BuildAndSignSignerProvisioningPackage(
    $privateOwnerKey,
    $password,
    $privateOwnerKey,
    $password,
    $identity
)

# Save the data to a binary file which can later be applied to any Surface device
# using the V2 version.
$signerProvisioningPackage = New-Object System.IO.Filestream($ownerPackageName, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
$stream.CopyTo($signerProvisioningPackage)
$signerProvisioningPackage.Close()

# Device owners will need the last two characters of the thumbprint to accept SEMM ownership.
# For convenience we get the thumbprint here and present to the user.
$pw = ConvertTo-SecureString $password -AsPlainText -Force
$certPrint = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
$certPrint.Import($privateOwnerKey, $pw, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
Write-Host "Thumbprint =" $certPrint.Thumbprint
Write-Host ""
Write-Host ""

# Create the universal reset package
$identity = [Microsoft.Surface.IUefiConfiguration+Identity]::SignerOwner
$stream = $uefiV2.BuildAndSignSignerProvisioningResetPackage(
    $privateOwnerKey,
    $password,
    $identity
)

# Save the data to a binary file which can later be applied to any Surface device
# using the V2 version.
$resetPackage = New-Object System.IO.Filestream($resetPackageName, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
$stream.CopyTo($resetPackage)
$resetPackage.Close()
