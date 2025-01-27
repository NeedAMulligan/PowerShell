param(
  [Parameter(
    Mandatory = $false,
    HelpMessage = "Get the users manager"
  )]
  [switch]$getManager = $true,

  [Parameter(
    Mandatory = $false,
    HelpMessage = "Get accounts that are enabled, disabled or both"
  )]
    [ValidateSet("true", "false", "both")]
  [string]$enabled = "true",

  [Parameter(
    Mandatory = $false,
    HelpMessage = "Enter path to save the CSV file"
  )]
  [string]$path = ".\ADUsers-$((Get-Date -format "MMM-dd-yyyy").ToString()).csv"
)

$ErrorActionPreference = "Stop"

Function Get-Users {
    <#
    .SYNOPSIS
      Get users from the requested DN
    #>
    process{
      # Set the properties to retrieve
      $properties = @(
        'ObjectId',
        'DisplayName',
        'userprincipalname',
        'mail',
        'jobtitle',
        'department',
        'telephoneNumber',
        'PhysicalDeliveryOfficeName',
        'mobile',
        'streetAddress',
        'city',
        'postalcode',
        'state',
        'country',
        'AccountEnabled'
      )

      # Get enabled, disabled or both users
      switch ($enabled)
      {
        "true" {$filter = "AccountEnabled eq true"}
        "false" {$filter = "AccountEnabled eq false"}
        "both" {$filter = ""}
      }

      # Get the users
      Get-AzureADUser -Filter $filter | select $properties
    }
}


Function Get-AllAzureADUsers {
  <#
    .SYNOPSIS
      Get all AD users
  #>
  process {
    Write-Host "Collecting users" -ForegroundColor Cyan
    $users = @()

    # Collect users
    $users += Get-Users

    # Loop through all users
    $users | ForEach {

      $manager = ""

      If (($getManager.IsPresent)) {
        # Get the users' manager
        $manager = Get-AzureADUserManager -ObjectId $_.ObjectId | Select -ExpandProperty DisplayName
      }

      [pscustomobject]@{
        "Name" = $_.DisplayName
        "UserPrincipalName" = $_.UserPrincipalName
        "Emailaddress" = $_.mail
        "Job title" = $_.JobTitle
        "Manager" = $manager
        "Department" = $_.Department
        "Office" = $_.PhysicalDeliveryOfficeName
        "Phone" = $_.telephoneNumber
        "Mobile" = $_.mobile
        "Enabled" = if ($_.AccountEnabled) {"enabled"} else {"disabled"}
        "Street" = $_.StreetAddress
        "City" = $_.City
        "Postal code" = $_.PostalCode
        "State" = $_.State
        "Country" = $_.Country
      }
    }
  }
}

Get-AllAzureADUsers | Sort-Object Name | Export-CSV -Path $path -NoTypeInformation

if ((Get-Item $path).Length -gt 0) {
  Write-Host "Report finished and saved in $path" -ForegroundColor Green

  # Open the CSV file
  Invoke-Item $path

}else{
  Write-Host "Failed to create report" -ForegroundColor Red
}