# This PowerShell script tests the SurfaceUefiManager assembly.
# It also provides sample code for using the component.


$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
Write-Host "Script is running from `"$($scriptPath)`""
Write-Host "will look for DLL in: $($scriptPath)\surfaceuefimanager.dll"

# Manually load the assembly from a known path - 
# -  please note there are several ways to load DLLs with powershell - 
# -  use the way that works best with your infrastructure.
$a1 = [Reflection.Assembly]::LoadFrom("$($scriptPath)\\surfaceuefimanager.dll")


# If you know that the UEFI administrator is set, then supply the password to unlock it
# If it is not currently set, then this is ignored
[Microsoft.Surface.FirmwareOption]::Unlock("1234")

$blimit = [Microsoft.Surface.FirmwareOption]::Find("BatteryLimitEnable")
# $blimit = [Microsoft.Surface.FirmwareOption]::Find("SecureBoot")
if ($blimit -ne $null)
{
    # Technically, all settings are null-terminated Unicode strings
    if ($blimit.CurrentValue -eq "1")
    {
	Write-Host "battery limit was 1, changed to 0"
	$blimit.ProposedValue = "0"
    }
    elseif( $blimit.CurrentValue -eq "0")
    {
	Write-Host "battery limit was 0, changed to 1"
	$blimit.ProposedValue = "1"
    }
    elseif( $blimit.CurrentValue -eq $null)
    {
	Write-Host "battery limit was NULL, changed to 0"
	$blimit.ProposedValue = "0"
    }
    else
    {
	Write-Host "battery limit was left untouched, was " $blimit.CurrentValue
    }
}
else
{
    Write-Host "Error: BatteryLimitEnable NVRAM variable not found!"
}

