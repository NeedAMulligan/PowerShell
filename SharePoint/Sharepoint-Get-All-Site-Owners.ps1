#Variables for Admin Center
$AdminCenterURL = "https://yoursite.sharepoint.com/"
$CSVPath = "C:\Temp\SiteOwners.csv"
  
#Get Credentials to connect
$Cred = Get-Credential
 
#Connect to SharePoint Online and Azure AD
Connect-SPOService -url $AdminCenterURL -Credential $Cred
Connect-AzureAD -Credential $Cred | Out-Null
   
#Get all Site Collections
$Sites = Get-SPOSite -Limit ALL
 
$SiteOwners = @()
#Get Site Owners for each site collection
$Sites | ForEach-Object {
    If($_.Template -like 'GROUP*')
    {
        $Site = Get-SPOSite -Identity $_.URL
        #Get Group Owners
        $GroupOwners = (Get-AzureADGroupOwner -ObjectId $Site.GroupID | Select -ExpandProperty UserPrincipalName) -join "; "      
    }
    Else
    {
        $GroupOwners = $_.Owner
    }
    #Collect Data
    $SiteOwners += New-Object PSObject -Property @{
    'Site Title' = $_.Title
    'URL' = $_.Url
    'Owner(s)' = $GroupOwners
    }
}
#Get Site Owners
$SiteOwners
 
#Export Site Owners report to CSV
$SiteOwners | Export-Csv -path $CSVPath -NoTypeInformation