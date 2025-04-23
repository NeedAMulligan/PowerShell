# --- Connect to the Microsoft Teams Module ---
# Replace with your credentials and organization information
$User = "<your_admin_account_email>"
$PassWord = ConvertTo-SecureString -String "<your_admin_password>" -AsPlainText -Force
$UserCredential = New-Object -TypeName "System.Management.Automation.PSCredential" -ArgumentList $User, $PassWord
Import-Module MicrosoftTeams
Connect-MicrosoftTeams -Credential $UserCredential -AccountId $User
# --- Get all Teams ---
$allTeams = Get-Team -All

# --- Loop through each Team and its Private Channels ---
foreach ($team in $allTeams) {
    # --- Get Private Channels for the Current Team ---
    $privateChannels = Get-TeamChannel -GroupID $team.GroupId | Where-Object {$_.ChannelType -eq "Private"}

    # --- Loop through each Private Channel ---
    foreach ($privateChannel in $privateChannels) {
        # --- Add the Admin User as an Owner ---
        # Replace with the admin user's UPN
        $adminUser = "<admin_user_UPN>"
        Add-TeamChannelUser -GroupId $team.GroupId -ChannelId $privateChannel.Id -User $adminUser -Role "Owner"
        Write-Host "Added $adminUser as owner to channel $($privateChannel.DisplayName) in team $($team.DisplayName)" -ForegroundColor Green
    }
}

# --- Disconnect from Microsoft Teams (Optional) ---
Disconnect-MicrosoftTeams