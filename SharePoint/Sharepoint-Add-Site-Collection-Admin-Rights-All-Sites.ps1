#Variables for processing
$AdminURL = "https://your-site.sharepoint.com/"
$AdminName="admin@your-admin.com"
 
#Connect to SharePoint Online
Connect-SPOService -url $AdminURL -credential (Get-Credential)
 
#Get All Site Collections
$AllSites = Get-SPOSite -Limit ALL
 
#Loop through each site and add site admins
Foreach ($Site in $AllSites)
{
    Write-host "Adding Site Collection Admin for:"$Site.URL
    Set-SPOUser -site $Site.Url -LoginName $AdminName -IsSiteCollectionAdmin $True
}