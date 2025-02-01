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
# CurrentSettings.ps1
#
# PURPOSE:
#  Display the current SEMM settings on the device at boot.
#
# RUNS ON:
#  Surface device.
#
# PREREQUISITES:
#  1) Run with administrator privileges
#  2) Surface Device has installed the SurfaceUefiManagerSetup.msi

# Load() is the recommended way to load the assembly, but it requires knowing the exact version
# [System.Reflection.Assembly]::LoadWithPartialName("SurfaceUefiManager")
[System.Reflection.Assembly]::Load("SurfaceUefiManager, Version=2.9.136.0, Culture=neutral, PublicKeyToken=fc3210b1ec5c11d4")


# You can use the UefiManager to detect the local device version
$uefi = [Microsoft.Surface.UefiManager]::CreateFromLocalDevice()

Write-Host "*** SMBIOS Settings ***"
Write-Host "Manufacturer:                 " $uefi.Manufacturer
Write-Host "SystemFamily:                 " $uefi.SystemFamily
Write-Host "Model:                        " $uefi.Model
Write-Host "UEFI Version:                 " $uefi.UefiVersion
Write-Host "Serial Number:                " $uefi.SerialNumber
Write-Host ""

Write-Host "*** SEMM Family and Version ***"
Write-Host "SEMM UEFI Family:             " $uefi.SurfaceUefiFamily
Write-Host "SEMM UEFI Settings Version:   " $uefi.SurfaceUefiSettingsVersion
Write-Host "SEMM Configuration Mechanism: " $uefi.ConfigurationMechanism
Write-Host ""

if ($uefi.ConfigurationMechanism -ne [Microsoft.Surface.IUefiConfiguration+ConfigurationMechanismEnum]::V2) {
    Write-Host -ForegroundColor Yellow "Unsupported device: " $uefi.Model
    Write-Host -ForegroundColor Yellow "Verify that SMBIOS settings are correct and that XML file"
    Write-Host -ForegroundColor Yellow "  C:\ProgramData\Microsoft\Surface\Devices\UefiVersions.xml"
    Write-Host -ForegroundColor Yellow "is up to date for this product SMBIOS settings."
    Exit
}

Write-Host "*** Settings At Boot ***"
Write-Host "Settings LSV: " $uefi.LowestSupportedSettingsPackageVersion
foreach ($setting IN $uefi.Settings.Values) {
    [Microsoft.Surface.IUefiLocalSetting] $localSetting = $setting
    Write-Host $localSetting.Name = $localSetting.ValueAtBoot
}
Write-Host ""

Write-Host "*** Permissions At Boot ***"
Write-Host "Permissions LSV: " $uefi.LowestSupportedPermissionPackageVersion
foreach ($setting IN $uefi.Settings.Values) {
    [Microsoft.Surface.IUefiLocalSetting] $localSetting = $setting
    Write-Host $localSetting.Name = $localSetting.PermissionAtBoot
}
Write-Host ""

Write-Host
Write-Host "*** SEMM Identity Key Thumbprints ***"
Write-Host "Signer: " $uefi.Thumbprints[[Microsoft.Surface.IUefiConfiguration+Identity]::SignerOwner]
Write-Host "User:   " $uefi.Thumbprints[[Microsoft.Surface.IUefiConfiguration+Identity]::SignerUser]
Write-Host "User1:  " $uefi.Thumbprints[[Microsoft.Surface.IUefiConfiguration+Identity]::SignerUser1]
Write-Host "USer2:  " $uefi.Thumbprints[[Microsoft.Surface.IUefiConfiguration+Identity]::SignerUser2]


$uefi | Select-Object *