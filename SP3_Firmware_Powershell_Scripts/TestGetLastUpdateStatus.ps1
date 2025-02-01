# This PowerShell script tests the SurfaceUefiManager assembly.
# It also provides sample code for using the component.

# Manually load the assembly from a known path
$a1 = [Reflection.Assembly]::LoadFrom('SurfaceUefiManager.dll')

# Get the overall status from the last proposed update
$updateStatus = [Microsoft.Surface.FirmwareOption]::UpdateStatus
$updateIteration = [Microsoft.Surface.FirmwareOption]::UpdateIteration
Write-Host "Last Update Status =" $updateStatus
Write-Host "Last Update Iteration =" $updateIteration

# Get the individual results for the last proposed update
# If the device has never had an update attempt this will be an empty list
$details = [Microsoft.Surface.FirmwareOption]::UpdateStatusDetails
Write-Host $details.Count "Settings were proposed"
if ($details.Count -gt 0)
{
    Write-Host "Result Details"
    foreach ($detail in $details.GetEnumerator())
    {
        Write-Host " " $detail.Key "=" $detail.Value
    }
}