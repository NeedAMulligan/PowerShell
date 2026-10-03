# Requires Active Directory module for PowerShell (for Get-ADDomain to get the root DN)
Import-Module ActiveDirectory

Write-Host "Configuring 'Protect object from accidental deletion' for all OUs (including nested OUs)..."
Write-Host "----------------------------------------------------------------------------------------------------------------"

# --- Configuration Section ---
# Set this to $true to ENABLE protection, $false to DISABLE protection
$EnableProtection = $true
# Set this to $true to perform the changes, $false for a dry-run (recommended for first run)
$PerformChanges = $false
# --- End Configuration Section ---

try {
    # Get the Distinguished Name of the current domain's root.
    $domainDN = (Get-ADDomain).DistinguishedName

    # Create a DirectoryEntry object for the search base (your domain root)
    $domainRoot = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$domainDN")

    # Create a DirectorySearcher object
    $searcher = New-Object System.DirectoryServices.DirectorySearcher($domainRoot)

    # Set the LDAP filter to find only Organizational Units
    $searcher.Filter = "(objectClass=organizationalUnit)"

    # Set the search scope to Subtree for deep traversal
    $searcher.SearchScope = [System.DirectoryServices.SearchScope]::Subtree

    # Add the properties you want to retrieve and potentially modify
    $searcher.PropertiesToLoad.Add("distinguishedName") | Out-Null
    $searcher.PropertiesToLoad.Add("protectedFromAccidentalDeletion") | Out-Null
    # We also need the ObjectGUID to use Set-ADObject for modification
    $searcher.PropertiesToLoad.Add("objectGUID") | Out-Null

    Write-Host "Executing search for Organizational Units, this may take a moment..."

    # Perform the search
    $results = $searcher.FindAll()

    if ($results.Count -eq 0) {
        Write-Warning "No Organizational Units found in this domain."
    } else {
        Write-Host "Found $($results.Count) Organizational Units."
        Write-Host "Attempting to set 'ProtectedFromAccidentalDeletion' to: $($EnableProtection)"
        Write-Host "Performing actual changes: $($PerformChanges)"
        Write-Host "---"

        foreach ($result in $results) {
            $ouPath = $result.Properties["distinguishedName"][0]
            $currentIsProtected = $result.Properties["protectedFromAccidentalDeletion"][0]
            $ouGuid = $result.Properties["objectGUID"][0] # Get the GUID for Set-ADObject

            Write-Host "Processing OU: '$ouPath'"
            Write-Host "  Current protection status: $($currentIsProtected)"

            # Check if a change is needed
            if ($currentIsProtected -ne $EnableProtection) {
                if ($PerformChanges) {
                    try {
                        # Use Set-ADObject with the GUID for reliability
                        # The -Identity parameter can accept a GUID
                        Set-ADObject -Identity $ouGuid -ProtectedFromAccidentalDeletion $EnableProtection -ErrorAction Stop
                        Write-Host "  ACTION: Successfully set protection to: $($EnableProtection)" -ForegroundColor Green
                    }
                    catch {
                        Write-Error "  ERROR: Failed to set protection for '$ouPath': $($_.Exception.Message)"
                    }
                } else {
                    Write-Host "  DRY RUN: Would set protection to: $($EnableProtection)" -ForegroundColor Yellow
                }
            } else {
                Write-Host "  No change needed. Protection is already set to: $($EnableProtection)"
            }
            Write-Host "" # Add a blank line for readability
        }
    }
}
catch {
    Write-Error "An unhandled error occurred: $($_.Exception.Message)"
    Write-Error "Ensure you have proper permissions and network connectivity to the domain controller."
}

Write-Host "----------------------------------------------------------------------------------------------------------------"
Write-Host "Script finished."
