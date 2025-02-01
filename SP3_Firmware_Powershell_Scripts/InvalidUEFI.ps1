# This PowerShell script tests the UEFI BootNext support and correct case for Boot#### variables
# Run this script, then plug in a USB device with the UEFI shell and reboot without pressing Volume Down.
# The device should reboot to the UEFI shell

# Manually load the assembly from a known path
$a1 = [Reflection.Assembly]::LoadFrom('SurfaceUefiManager.dll')

[Microsoft.Surface.FirmwareOption]::Find("SecureBoot")
if ($secureBoot -ne $null)
{
    # Technically, all settings are null-terminated Unicode strings
	$secureBoot.ProposedValue = "TEST"
}

