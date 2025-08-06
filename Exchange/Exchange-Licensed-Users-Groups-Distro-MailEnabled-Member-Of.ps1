# Check if C:\temp directory exists, and create it if it doesn't
$tempDir = "C:\temp"
if (-not (Test-Path $tempDir)) {
    Write-Host "Directory $tempDir not found. Creating it now..." -ForegroundColor Yellow
    New-Item -Path $tempDir -ItemType Directory | Out-Null
}

# Generate a dynamic filename with the current date and time
$date = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$fileName = "LicensedUsersAndGroups_$date.csv"
$outputPath = Join-Path -Path $tempDir -ChildPath $fileName

Write-Host "Getting all licensed users from Exchange Online..." -ForegroundColor Green

# Get all users with a license
# We filter for users with a UsageLocation specified, which is a good indicator of a licensed user
$licensedUsers = Get-EXOUser -ResultSize Unlimited -Filter "UsageLocation -ne `$null" | Select-Object DisplayName, UserPrincipalName

# Check if any licensed users were found
if ($licensedUsers.Count -eq 0) {
    Write-Host "No licensed users found. Exiting script." -ForegroundColor Yellow
    exit
}

# Create an array to hold the output data
$outputData = @()

Write-Host "Processing each user to find group memberships..." -ForegroundColor Green

# Loop through each licensed user
foreach ($user in $licensedUsers) {
    Write-Host "Processing user: $($user.DisplayName) - $($user.UserPrincipalName)" -ForegroundColor Cyan

    try {
        # Get all distribution groups and mail-enabled security groups the user is a member of
        $groups = Get-EXOUser -Identity $user.UserPrincipalName | Select-Object -ExpandProperty MemberOfGroup

        # Initialize an array for group names
        $groupNames = @()

        # Check if the user is a member of any groups
        if ($groups -ne $null) {
            # Get the display name for each group and add it to the array
            foreach ($group in $groups) {
                $groupNames += $group.DisplayName
            }
        }

        # Create a custom object with the user's details and their groups
        $userData = [PSCustomObject]@{
            DisplayName          = $user.DisplayName
            UserPrincipalName    = $user.UserPrincipalName
            DistributionGroups   = ($groupNames -join ", ")
        }

        # Add the custom object to the output array
        $outputData += $userData

    } catch {
        Write-Host "Error processing user $($user.UserPrincipalName): $_" -ForegroundColor Red
    }
}

# Export the data to a CSV file
Write-Host "Exporting data to $($outputPath)..." -ForegroundColor Green
$outputData | Export-Csv -Path $outputPath -NoTypeInformation

Write-Host "Script finished. The report has been saved to: $($outputPath)" -ForegroundColor Green
