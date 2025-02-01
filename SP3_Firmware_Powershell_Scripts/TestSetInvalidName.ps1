# This PowerShell script tests the SurfaceUefiManager assembly.
# It also provides sample code for using the component.

# Manually load the assembly from a known path
$a1 = [Reflection.Assembly]::LoadFrom('SurfaceUefiManager.dll')

# If you know that the UEFI administrator is set, then supply the password to unlock it
# If it is not currently set, then this is ignored
[Microsoft.Surface.FirmwareOption]::Unlock("1234")

$opt = [Microsoft.Surface.FirmwareOption]::Find("InvalidName")
if ($opt -ne $null)
{
    $opt.ProposedValue = "123"
}

