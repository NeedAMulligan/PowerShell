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
# ShowSettingsOptions.ps1
#
# PURPOSE:
#  Prints the UEFI settings that can be applied to Surface devices.
#
# RUNS ON:
#  IT Administrator workstation (does not need to be a Surface device)
#
# PREREQUISITES:
#  1) IT Adminstrator workstation has installed the SurfaceUefiManagerSetup.msi

# Load() is the recommended way to load the assembly, but it requires knowing the exact version
# [System.Reflection.Assembly]::LoadWithPartialName("SurfaceUefiManager")
[System.Reflection.Assembly]::Load("SurfaceUefiManager, Version=2.9.136.0, Culture=neutral, PublicKeyToken=fc3210b1ec5c11d4")

# The UEFI manager class knows about all currently supported Surface devices.
$uefiManager = New-Object -TypeName Microsoft.Surface.UefiManager
$uefiManager.LoadKnownUefiConfigurations()

# The settings and permission packages are dependent on the specific device and even UEFI version.
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

# Display what settings are available and their IDs
foreach ($uefi IN $surfaceDevices.Values) {
    Write-Host -ForegroundColor Gray "*** " $uefi.SurfaceUefiFamilyAndVersion " ***"
    foreach ($setting IN $uefi.Settings.Values) {
        Write-Host -ForegroundColor Gray $setting.ID "=" $setting.Name
        Write-Host -ForegroundColor Gray "  Description: " $setting.Help
        Write-Host -ForegroundColor Gray "  Default: " $setting.DefaultValue
        Write-Host
    }
    Write-Host
}
