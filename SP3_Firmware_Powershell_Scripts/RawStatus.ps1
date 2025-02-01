# This PowerShell script tests the SurfaceUefiManager assembly.
# It also provides sample code for using the component.

# Manually load the assembly from a known path
$a1 = [Reflection.Assembly]::LoadFrom('SurfaceUefiManager.dll')

# Get the overall status from the last proposed update
$nvram = new-object Microsoft.Surface.NvramAccessor
$rawStatus = $nvram.GetVariable("UpdateStatus", "{6346E112-9186-4771-ACF0-57285239F808}")
Write-Host "Raw Update Status =" $rawStatus
$proposedUnlock = $nvram.GetVariable("Unlock", "{C518696F-2717-4EFE-AA2F-82808B3B1873}")
if ($proposedUnlock -eq $null)
{
    $proposedUnlock = "<Not Set>"
}

Write-Host "Unlock =" $proposedUnlock 
#$proposedPassword = $nvram.GetVariable("Password", "{C518696F-2717-4EFE-AA2F-82808B3B1873}")

$SecureBoot= $nvram.GetVariable("Secure Boot", "{C518696F-2717-4EFE-AA2F-82808B3B1873}")
if ($proposedPassword -eq $null)
{
    $proposedPassword = "<Not Set>"
}

Write-Host "Secureboot Value = " ($proposedPassword)
Write-Host "Password =" $proposedPassword
