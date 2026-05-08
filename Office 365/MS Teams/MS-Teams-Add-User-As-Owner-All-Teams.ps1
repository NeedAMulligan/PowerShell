    Connect-MicrosoftTeams
    $AllTeams = Get-Team
    foreach ($Team in $AllTeams) {
      Add-TeamUser -GroupId $Team.GroupID -User "owner@example.com" -Role Owner
    }