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
# VerifySettings.ps1
#
# PURPOSE:
#  Demonstrates how to see the current settings and state of recent updates.
#
# RUNS ON:
#  Surface device you have applied configuration packages to.
#
# PREREQUISITES:
#  1) Run with administrator privileges
#  2) Surface Device has installed the SurfaceUefiManagerSetup.msi
#  3) Packages were applied and the session ID files saved.
#
$WorkingDirPath = split-path -parent $MyInvocation.MyCommand.Definition
$demoRoot = "$WorkingDirPath\Config"

if (-not (Test-Path $demoRoot))  { New-Item -ItemType Directory -Force -Path $demoRoot }

# Load() is the recommended way to load the assembly, but it requires knowing the exact version
# [System.Reflection.Assembly]::LoadWithPartialName("SurfaceUefiManager")
[System.Reflection.Assembly]::Load("SurfaceUefiManager, Version=2.9.136.0, Culture=neutral, PublicKeyToken=fc3210b1ec5c11d4")

# You can use the UefiManager to detect the local device version
$uefi = [Microsoft.Surface.UefiManager]::CreateFromLocalDevice()
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

# Read session IDs saved to file
$ownerSessionIdString = "<None>"
$sessionFile = Join-Path -Path $demoRoot -ChildPath "OwnerSessionId.txt"
if (Test-Path $sessionFile) {
    $reader = New-Object System.IO.StreamReader($sessionFile)
    $ownerSessionIdString = $reader.ReadLine()
    $reader.Close()
}

$permissionSessionIdString = "<None>"
$sessionFile = Join-Path -Path $demoRoot -ChildPath "PermissionSessionId.txt"
if (Test-Path $sessionFile) {
    $reader = New-Object System.IO.StreamReader($sessionFile)
    $permissionSessionIdString = $reader.ReadLine()
    $reader.Close()
}

$settingsSessionIdString = "<None>"
$sessionFile = Join-Path -Path $demoRoot -ChildPath "SettingsSessionId.txt"
if (Test-Path $sessionFile) {
    $reader = New-Object System.IO.StreamReader($sessionFile)
    $settingsSessionIdString = $reader.ReadLine()
    $reader.Close()
}

# Write the overall package update information
Write-Host
Write-Host "*** Overall results of applied packages ***"
Write-Host "  Ownership package:"
Write-Host "    Expected Session ID:               " $ownerSessionIdString
Write-Host "    Session ID returned from UEFI:     " $uefi.LastSignerProvisioningUpdateSessionId
$msg = [string]::Format("    Update Status                :      x{0:X16}", $uefi.LastSignerProvisioningUpdateStatus)
Write-Host $msg

Write-Host "  Permission package:"
Write-Host "    Current LSV:                       " $uefi.LowestSupportedPermissionPackageVersion
Write-Host "    Expected Session ID:               " $permissionSessionIdString
Write-Host "    Session ID returned from UEFI:     " $uefi.LastPermissionUpdateSessionId
$msg = [string]::Format("    Update Status                :      x{0:X16}", $uefi.LastPermissionUpdateStatus)
Write-Host $msg

Write-Host "  Settings package:"
Write-Host "    Current LSV:                       " $uefi.LowestSupportedSettingsPackageVersion
Write-Host "    Expected Session ID:               " $settingsSessionIdString
Write-Host "    Session ID returned from UEFI:     " $uefi.LastSecuredSettingsUpdateSessionId
$msg = [string]::Format("    Update Status                :      x{0:X16}", $uefi.LastSecuredSettingsUpdateStatus)
Write-Host $msg

# Individual settings
# These will not be available until device is placed in SEMM mode
Write-Host
Write-Host "*** UEFI setting value at boot ***"
foreach ($setting in $uefi.SettingsById.Values) {
    Write-Host $setting.Name " (" $setting.ID ") = " $setting.ValueAtBoot
}

# Here are the permissions as hex
Write-Host
Write-Host "*** UEFI setting permissions at boot ***"
foreach ($setting in $uefi.SettingsById.Values) {
    $msg = [string]::Format("{0} ({1}) = x{2:X4}", $setting.Name, $setting.ID, $setting.PermissionAtBoot)
    Write-Host $msg
}

# More details of exactly what went wrong with a settings package attempt
Write-Host
Write-Host "*** Status of most recent settings update ***"
foreach ($setting in $uefi.SettingsById.Values) {
    $msg = [string]::Format("{0} ({1}) = x{2:X16}", $setting.Name, $setting.ID, $setting.LastUpdateStatus)
    Write-Host $msg
}
