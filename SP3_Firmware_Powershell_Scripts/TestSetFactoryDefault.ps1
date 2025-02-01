# This PowerShell script tests the SurfaceUefiManager assembly.
# It also provides sample code for using the component.

# Manually load the assembly from a known path
$a1 = [Reflection.Assembly]::LoadFrom('c:\Temp\SurfaceUefiManager.dll')

# If you know that the UEFI administrator is set, then supply the password to unlock it
# If it is not currently set, then this is ignored
[Microsoft.Surface.FirmwareOption]::Unlock("1234")

# Get the collection of all configurable settings
$uefiOptions = [Microsoft.Surface.FirmwareOption]::All()

# Reset all options to the factory default
foreach ($uefiOption in $uefiOptions)
{
    $uefiOption.ProposedValue = $uefiOption.DefaultValue
}