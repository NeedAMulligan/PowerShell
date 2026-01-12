# Requires the Microsoft.Graph and Microsoft.Graph.Sites modules.
# If not installed, run:
# Install-Module Microsoft.Graph -Scope CurrentUser
# Install-Module Microsoft.Graph.Sites -Scope CurrentUser

# --- Configuration ---
$tenantUrl = "https://rogercogcc-admin.sharepoint.com"
$exportPath = "C:\temp\"
$userEmail = Read-Host "Please enter the user's email address to check"

# --- Script Logic ---

# Check if the export directory exists, create it if not
if (-not (Test-Path -Path $exportPath)) {
    Write-Host "Creating directory: $exportPath"
    New-Item -ItemType Directory -Path $exportPath -Force
}

# Dynamic file naming convention
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$fileName = "Graph_SharePoint_Site_Membership_$($userEmail)_$($timestamp).csv"
$fullPath = Join-Path -Path $exportPath -ChildPath $fileName

Write-Host "Connecting to Microsoft Graph..."
try {
    # Connect to Microsoft Graph with the necessary scopes
    Connect-MgGraph -Scopes "Group.Read.All", "Sites.Read.All", "User.Read.All"

    # Get the user's object to retrieve their ID
    $user = Get-MgUser -Filter "mail eq '$userEmail'"
    if (-not $user) {
        throw "User with email '$userEmail' not found. Please ensure the user exists and the email is correct."
    }
    $userId = $user.Id

    # Use Get-MgSite to retrieve all SharePoint sites
    Write-Host "Retrieving all SharePoint sites. This may take a moment..."
    $sites = Get-MgSite -All | Where-Object { $_.WebUrl -notlike '*my.sharepoint.com*' }

    # Initialize an array to hold the results
    $results = @()

    Write-Host "Checking site permissions for user: $userEmail"

    foreach ($site in $sites) {
        try {
            Write-Host "Processing site: $($site.DisplayName) - $($site.WebUrl)"
            
            # Use Microsoft Graph to check group membership
            $siteGroups = Get-MgGroup -Filter "resourceProvisioningOptions/Any(x:x eq 'Team')" | Where-Object { $_.SitesUrl -eq $site.WebUrl }
            
            $isMember = $false
            foreach ($group in $siteGroups) {
                # Get the members of each group and check if the user's ID exists
                $groupMembers = Get-MgGroupMember -GroupId $group.Id -All
                if ($groupMembers.Id -contains $userId) {
                    $isMember = $true
                    break
                }
            }
            
            if ($isMember) {
                $siteObject = [PSCustomObject]@{
                    SiteTitle         = $site.DisplayName
                    SiteUrl           = $site.WebUrl
                    UserEmail         = $userEmail
                    RoleOnSite        = "Member (via Group)"
                    LastModifiedDate  = $site.LastModifiedDateTime
                }
                $results += $siteObject
            }
        }
        catch {
            Write-Warning "Could not process site $($site.WebUrl). Error: $_.Exception.Message"
            # Disconnect and reconnect to handle potential session issues
            Disconnect-MgGraph
            Connect-MgGraph -Scopes "Group.Read.All", "Sites.Read.All", "User.Read.All" -Force
        }
    }

    # Export the results to a CSV file
    if ($results.Count -gt 0) {
        $results | Export-Csv -Path $fullPath -NoTypeInformation -Force
        Write-Host "Successfully exported the user's SharePoint site membership to: $fullPath" -ForegroundColor Green
    } else {
        Write-Host "The user '$userEmail' was not found to be a member of any SharePoint sites." -ForegroundColor Yellow
    }

}
catch {
    Write-Host "An error occurred during the script execution. Please check the error message below." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}
finally {
    # Disconnect from Microsoft Graph
    Disconnect-MgGraph
}
