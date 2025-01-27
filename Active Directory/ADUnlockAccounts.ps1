#Quicky unlocks domain user accounts
Import-Module ActiveDirectory 
Search-ADAccount -LockedOut
$caption = "Confirm";
$message = "Unlock User(s)?";
$yes = new-Object System.Management.Automation.Host.ChoiceDescription "&Yes","help";
$no = new-Object System.Management.Automation.Host.ChoiceDescription "&No","help";
$choices = [System.Management.Automation.Host.ChoiceDescription[]]($yes,$no);
$answer = $host.ui.PromptForChoice($caption,$message,$choices,0)

switch ($answer){
    0 {"You entered yes"; break}
    1 {"You entered no"; break}
}

write-host "User Account(s) Unlocked!"
Search-ADAccount -LockedOut | Unlock-ADAccount
