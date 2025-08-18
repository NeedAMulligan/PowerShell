<#
.SYNOPSIS
    Exports a list of SharePoint sites where a specified user is a member or owner.

.DESCRIPTION
    This script uses the PnP.PowerShell module to connect to a SharePoint Online tenant,
    retrieve all site collections, and then check each site for the specified user's
    membership or ownership. The results are exported to a CSV file with a dynamic
    naming convention in the C:\temp directory.

.NOTES
    Author: Gemini AI
    Version: 1.0
    Requires: PnP.PowerShell module. If not installed, run: Install-Module PnP.PowerShell

.EXAMPLE
    PS C:\> .\Export-SharePointSites.ps1
    # This will prompt you to enter the user's email address and sign in.
#>

# --- How to Use the Script ---
<#
1.  **Prerequisites:** You must have the PnP.PowerShell module installed. If you don't, open a PowerShell terminal and run:
    `Install-Module PnP.PowerShell`
    You may need to run PowerShell as an administrator to install modules.

2.  **Configuration:** Replace the placeholder `https://yourtenant.sharepoint.com` with your actual SharePoint tenant URL.

3.  **Run the script:** Save this code as a `.ps1` file (e.g., `Export-SharePointSites.ps1`). Open a PowerShell console, navigate to the script's location, and run it:
    `.\Export-SharePointSites.ps1`

4.  **Follow the prompts:** The script will ask you for the user's email address and then open a browser window for you to sign in with an account that has SharePoint administrative privileges.

5.  **Check the output:** The results will be exported to a CSV file in the `C:\temp\` directory with a dynamic name like `SharePoint_Site_Membership_user@domain.com_20250806_094500.csv`.
#>


# --- Configuration ---
$tenantUrl = "https://rogercogcc-admin.sharepoint.com/"  # <<< IMPORTANT: Replace with your SharePoint tenant URL
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
$fileName = "SharePoint_Site_Membership_$($userEmail)_$($timestamp).csv"
$fullPath = Join-Path -Path $exportPath -ChildPath $fileName

Write-Host "Connecting to SharePoint Online tenant: $tenantUrl..."
try {
    # Connect to the SharePoint Online Admin Center
    Connect-PnPOnline -Url $tenantUrl -Interactive

    # Get all site collections and sites
    Write-Host "Retrieving all SharePoint sites. This may take a moment..."
    $sites = Get-PnPTenantSite -Detailed -Filter "Url -ne '$tenantUrl'" | Where-Object { $_.Url -notlike '*my.sharepoint.com*' }

    # Initialize an array to hold the results
    $results = @()

    Write-Host "Checking site permissions for user: $userEmail"

    foreach ($site in $sites) {
        try {
            # Connect to each site
            Connect-PnPOnline -Url $site.Url -Interactive -WarningAction SilentlyContinue

            # Check if the user is a member of any SharePoint group on the site
            $groups = Get-PnPGroup -ErrorAction SilentlyContinue | Where-Object { $_.Users.Email -contains $userEmail }

            # Check if the user has specific permissions on the site (e.g., as an owner or a direct permission assignment)
            $hasPermissions = Get-PnPUser -Identity $userEmail -ErrorAction SilentlyContinue
            
            # Check if the user is a site collection administrator
            $siteAdmins = Get-PnPTenantSite -Identity $site.Url | Select-Object -ExpandProperty Owners
            $isSiteAdmin = $siteAdmins -contains $userEmail

            if ($groups.Count -gt 0 -or $hasPermissions -ne $null -or $isSiteAdmin) {
                $role = "Member"
                if ($isSiteAdmin) {
                    $role = "Site Collection Administrator"
                } elseif ($groups.Count -gt 0) {
                    $role = "Member of Group(s): " + ($groups.Title -join ', ')
                } elseif ($hasPermissions -ne $null) {
                    $role = "Direct Permissions"
                }

                # Create a custom object for the current site
                $siteObject = [PSCustomObject]@{
                    SiteTitle         = $site.Title
                    SiteUrl           = $site.Url
                    UserEmail         = $userEmail
                    RoleOnSite        = $role
                    Template          = $site.Template
                    HubSiteId         = $site.HubSiteId
                    LastContentModifiedDate = $site.LastContentModifiedDate
                }
                $results += $siteObject
            }
        }
        catch {
            Write-Warning "Could not connect to site $($site.Url). Error: $_.Exception.Message"
        }
    }

    # Export the results to a CSV file
    if ($results.Count -gt 0) {
        $results | Export-Csv -Path $fullPath -NoTypeInformation -Force
        Write-Host "Successfully exported the user's SharePoint site membership to: $fullPath" -ForegroundColor Green
    } else {
        Write-Host "The user '$userEmail' was not found to be a member or owner of any SharePoint sites." -ForegroundColor Yellow
    }

}
catch {
    Write-Host "An error occurred during the script execution. Please check the error message below." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}
finally {
    # Disconnect from SharePoint Online
    Disconnect-PnPOnline
}