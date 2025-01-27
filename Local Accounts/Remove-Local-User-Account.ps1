$userName = "user2"
$checkForUser = (Get-LocalUser).Name -Contains $userName

if ($checkForUser -eq "$true") {
    Write-Host "$username exists"
    Write-Host "deleting $username"
    Remove-LocalUser -Name "$username"
    }
else {
    Write-Host $username does not exist
    }
    