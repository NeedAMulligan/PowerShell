$teams = Get-Team
$count = 0
foreach ($team in $teams) {  
    $owner = Get-TeamUser -GroupId $team.GroupId -Role Owner
    if ($owner.User -eq "Tamara.Williams") {
        $team.DisplayName
        $count++
    }
} "found $count teams where the target user is owner"