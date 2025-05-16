Get-DistributionGroup -ResultSize unlimited | select Name, primarysmtpaddress, RequireSenderAuthenticationEnabled | Export-Csv -Path c:\temp\roger-groups_sender.csv -notypeinformation


# Get all distribution groups
$DistributionGroups = Get-DistributionGroup

# Create an empty array to store the results
$Results = @()

# Loop through each distribution group
foreach ($Group in $DistributionGroups) {
    # Get the join and leave restrictions for the current group
    $JoinRestriction = $Group | Get-DistributionGroup | Select-Object -ExpandProperty MemberJoinRestriction
    $LeaveRestriction = $Group | Get-DistributionGroup | Select-Object -ExpandProperty MemberDepartRestriction

    # Create a custom object to store the group name and its restrictions
    $Result = [PSCustomObject]@{
        GroupName       = $Group.Name
        JoinRestriction = $JoinRestriction
        LeaveRestriction = $LeaveRestriction
    }

    # Add the custom object to the results array
    $Results += $Result
}

# Export the results to a CSV file
$Results | Export-Csv -Path "C:\DistributionGroupRestrictions.csv" -NoTypeInformation

Write-Host "Distribution group restrictions exported to C:\DistributionGroupRestrictions.csv"
