<#
.SYNOPSIS
    Get-LockedOutUser.ps1 returns a list of users who were locked out in Active Directory.
 
.DESCRIPTION
    Get-LockedOutUser.ps1 is an advanced script that returns a list of users who were locked out in Active Directory
by querying the event logs on the PDC emulation in the domain.

This “Get-LockedOutUser.ps1“ script allows you to specify the following via parameter input to narrow down the results:

Specific userid, defaulting to all locked out userid’s
Start time to begin searching records for, defaulting to the last three days
Domain name to search for lockouts in, defaulting to the user’s domain who is running the script

Note: This script uses the "Using" scope modifier which is a feature that was introduced in PowerShell version 3 so that is the minimum requirement. Note that the error: "A null value was encountered in the StartTime hash table key. Null values are not permitted." will be generated if you attempt to run this script from a machine that is running PowerShell version 2.

For more information about this script, visit my blog article about it: "PowerShell Script to Determine What Device is Locking Out an Active Directory User Account".
 
.PARAMETER UserName
    The userid of the specific user you are looking for lockouts for. The default is all locked out users.
 
.PARAMETER StartTime
    The datetime to start searching from. The default is all datetimes that exist in the event logs.
 
.EXAMPLE
    Get-LockedOutUser.ps1
 
.EXAMPLE
    Get-LockedOutUser.ps1 -UserName 'mike'
 
.EXAMPLE
    Get-LockedOutUser.ps1 -StartTime (Get-Date).AddDays(-1)
 
.EXAMPLE
    Get-LockedOutUser.ps1 -UserName 'miker' -StartTime (Get-Date).AddDays(-1)
#>

[CmdletBinding()]
param (
    [ValidateNotNullOrEmpty()]
    [string]$DomainName = $env:USERDOMAIN,

    [ValidateNotNullOrEmpty()]
    [string]$UserName = "*",

    [ValidateNotNullOrEmpty()]
    [datetime]$StartTime = (Get-Date).AddDays(-3)
)

Invoke-Command -ComputerName (

    [System.DirectoryServices.ActiveDirectory.Domain]::GetDomain((
        New-Object System.DirectoryServices.ActiveDirectory.DirectoryContext('Domain', $DomainName))
    ).PdcRoleOwner.name

) {

Get-WinEvent -FilterHashtable @{LogName='Security';Id=4740;StartTime=$Using:StartTime} |
    Where-Object {$_.Properties[0].Value -like "$Using:UserName"} |
    Select-Object -Property TimeCreated, 
        @{Label='UserName';Expression={$_.Properties[0].Value}},
        @{Label='ClientName';Expression={$_.Properties[1].Value}}


} -Credential (Get-Credential) |
Select-Object -Property TimeCreated, 'UserName', 'ClientName'
