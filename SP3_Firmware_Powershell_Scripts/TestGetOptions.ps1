# This PowerShell script tests the SurfaceUefiManager assembly.
# It also provides sample code for using the component.

# Manually load the assembly from a known path
$a1 = [Reflection.Assembly]::LoadFrom('SurfaceUefiManager.dll')

# Get the collection of all configurable settings
$uefiOptions = [Microsoft.Surface.FirmwareOption]::All()

$nvram = new-object Microsoft.Surface.NvramAccessor
#$proposedUnlock = $nvram.SetVariable("Unlock", "{C518696F-2717-4EFE-AA2F-82808B3B1873}", "JASON")
$proposedUnlock = $nvram.GetVariable("Unlock", "{C518696F-2717-4EFE-AA2F-82808B3B1873}")
if ($proposedUnlock -eq $null)
{
    $proposedUnlock = "<Not Set>"
}

Write-Host "Unlock =" $proposedUnlock 

foreach ($uefiOption in $uefiOptions)
{
    Write-Host "Name:" $uefiOption.Name
    Write-Host " Description =" $uefiOption.Description
    Write-Host " Current Value =" $uefiOption.CurrentValue
    Write-Host " Default Value =" $uefiOption.DefaultValue
    $proposed = $uefiOption.ProposedValue
    if ($proposed -eq $null)
    {
        $proposed = "<Not Set>"
    }
    Write-Host " Proposed Value =" $proposed
    Write-Host
}