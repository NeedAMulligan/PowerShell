



# This PowerShell script tests the SurfaceUefiManager assembly.
# It also provides sample code for using the component.

# Manually load the assembly from a known path
$a1 = [Reflection.Assembly]::LoadFrom('SurfaceUefiManager.dll')

# If you know that the UEFI administrator is set, then supply the password to unlock it
# If it is not currently set, then this is ignored
[Microsoft.Surface.FirmwareOption]::Unlock("1234")
$secureBoot = [Microsoft.Surface.FirmwareOption]::Find("FrontCamera")
if ($secureBoot -ne $null)
{
    # Technically, all settings are null-terminated Unicode strings
	$secureBoot.ProposedValue = "00"
}

$secureBoot = [Microsoft.Surface.FirmwareOption]::Find("TPM")
if ($secureBoot -ne $null)
{
    # Technically, all settings are null-terminated Unicode strings
	$secureBoot.ProposedValue = "00"
}

$secureBoot = [Microsoft.Surface.FirmwareOption]::Find("SecureBoot")
if ($secureBoot -ne $null)
{
    # Technically, all settings are null-terminated Unicode strings
	$secureBoot.ProposedValue = "00"
}

$secureBoot = [Microsoft.Surface.FirmwareOption]::Find("FrontCamera")
if ($secureBoot -ne $null)
{
    # Technically, all settings are null-terminated Unicode strings
	$secureBoot.ProposedValue = "00"
}

$secureBoot = [Microsoft.Surface.FirmwareOption]::Find("RearCamera")
if ($secureBoot -ne $null)
{
    # Technically, all settings are null-terminated Unicode strings
	$secureBoot.ProposedValue = "00"
}



$secureBoot = [Microsoft.Surface.FirmwareOption]::Find("WiFi")
if ($secureBoot -ne $null)
{
    # Technically, all settings are null-terminated Unicode strings
	$secureBoot.ProposedValue = "00"
}

$secureBoot = [Microsoft.Surface.FirmwareOption]::Find("Bluetooth")
if ($secureBoot -ne $null)
{
    # Technically, all settings are null-terminated Unicode strings
	$secureBoot.ProposedValue = "00"
}

$secureBoot = [Microsoft.Surface.FirmwareOption]::Find("Audio")
if ($secureBoot -ne $null)
{
    # Technically, all settings are null-terminated Unicode strings
	$secureBoot.ProposedValue = "00"
}

$secureBoot = [Microsoft.Surface.FirmwareOption]::Find("SdPort")
if ($secureBoot -ne $null)
{
    # Technically, all settings are null-terminated Unicode strings
	$secureBoot.ProposedValue = "00"
}


$secureBoot = [Microsoft.Surface.FirmwareOption]::Find("AltBootOrder")
if ($secureBoot -ne $null)
{
    # Technically, all settings are null-terminated Unicode strings
	$secureBoot.ProposedValue = "00"
}
