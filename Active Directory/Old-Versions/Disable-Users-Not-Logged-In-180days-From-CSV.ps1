# Specify the path to your CSV file
$csvFilePath = "C:\temp\users-180-days.csv"

# Specify the Distinguished Name (DN) of your "Disabled Users" OU
# !!! IMPORTANT: Replace 'OU=Disabled Users,DC=yourdomain,DC=com' with your actual OU path !!!
$disabledUsersOU = "OU=Disabled Users,DC=yourdomain,DC=com"

# Get the current date for the description
$disableDate = Get-Date -Format "yyyy-MM-dd"

# Import the Active Directory module (make sure it's installed)
Import-Module ActiveDirectory

# Read the CSV file
$usersToDisable = Import-Csv -Path $csvFilePath

foreach ($user in $usersToDisable) {
    $samAccountName = $user.SamAccountName # Assuming your CSV has a column named SamAccountName

    Write-Host "Processing user: $samAccountName"

    # Check if the user exists in Active Directory
    try {
        $adUser = Get-ADUser -Identity $samAccountName -ErrorAction Stop
    }
    catch {
        Write-Warning "User '$samAccountName' not found in Active Directory. Skipping."
        continue
    }

    # --- Step 1: Update the user's description ---
    $newDescription = "Disabled with date: $disableDate"
    try {
        Set-ADUser -Identity $adUser -Description $newDescription -ErrorAction Stop
        Write-Host "  - Description updated to '$newDescription'."
    }
    catch {
        Write-Warning "  - Failed to update description for '$samAccountName': $($_.Exception.Message)"
        # Decide if you want to continue or skip if description update fails
        # continue
    }

    # --- Step 2: Disable the user's account ---
    try {
        Disable-ADAccount -Identity $adUser -ErrorAction Stop
        Write-Host "  - Account disabled."
    }
    catch {
        Write-Warning "  - Failed to disable account for '$samAccountName': $($_.Exception.Message)"
        # Decide if you want to continue or skip if disabling fails
        # continue
    }

    # --- Step 3: Move the user to the Disabled Users OU ---
    try {
        Move-ADObject -Identity $adUser -TargetPath $disabledUsersOU -ErrorAction Stop
        Write-Host "  - User moved to '$disabledUsersOU'."
    }
    catch {
        Write-Warning "  - Failed to move user '$samAccountName' to '$disabledUsersOU': $($_.Exception.Message)"
        # Decide if you want to continue or skip if move fails
        # continue
    }

    Write-Host "" # Add a blank line for readability between users
}

Write-Host "Script finished."
