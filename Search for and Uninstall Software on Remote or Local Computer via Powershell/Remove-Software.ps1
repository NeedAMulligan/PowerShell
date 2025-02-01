<#
.SYNOPSIS
	This script removes any software registered via Windows Installer from a computer.    
.NOTES
	Created on:   	5/19/2014 2:59 PM
	Created by:   	Adam Bertram
	Filename:       Remove-Software.ps1
	Requirements:   Installed SCCM Client, the application's MSI (if no locally cached copy)
.DESCRIPTION
	This script searches the local computer for a specified application matching a name.
	It then checks to ensure the locally cached MSI exists in case the original source
	files are needed.  If then proceeds with the uninstall string if so.  If not, it will
	utilize the MSI included in the current directory to kick off the uninstall.
.EXAMPLE
	.\Remove-Software.ps1 -ProductName 'Adobe Reader' -MsiName 'setup.msi'   
.EXAMPLE
    .\Remove-Software.ps1 -ProductName 'Adobe Reader'
.PARAMETER ProductName
	This is the name of the application to search for.
.PARAMETER MsiName
	This is the name of the MSI file that exists in the current directory.  If no MSI file is 
	specified, the script will search for and use the first MSI it finds in the current directory.
#>
[CmdletBinding()]
param (
	[Parameter(Mandatory = $True,
			   ValueFromPipeline = $True,
			   ValueFromPipelineByPropertyName = $True)]
	[string]$ProductName,
	[Parameter(Mandatory = $False,
			   ValueFromPipeline = $False,
			   ValueFromPipelineByPropertyName = $False)]
	[string]$MsiName
)

begin {
	$WorkingDir = $MyInvocation.MyCommand.Path | Split-Path -Parent
	$SccmClientWmiNamespace = 'root\cimv2\sms'
	
	if ($MsiName) {
		$PackageMsiFilePath = "$WorkingDir\$MsiName"
	}
	
	
}

process {
	try {
		$Query = "SELECT * FROM SMS_InstalledSoftware WHERE ARPDisplayName LIKE '%$ProductName%'"
		Write-Verbose "Querying computer for the existence of $ProductName..."
		$InstalledSoftware = Get-WmiObject -Namespace $SccmClientWmiNamespace -Query $Query
		if ($InstalledSoftware) {
			$InstalledSoftware | foreach {
				Write-Verbose "$ProductName ($($_.SoftwareCode)) found installed..."
				Write-Verbose "Ensuring there's a valid uninstall string found..."
				if ($_.UninstallString.Trim() -match 'msiexec.exe /x{(\{){0,1}[0-9a-fA-F]{8}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{12}(\}){0,1}}') {
					Write-Verbose "Valid uninstall string found for $ProductName..."
					Write-Verbose "Ensuring a locally cached copy of the $ProductName MSI exists..."
					if (Test-Path $_.LocalPackage) {
						Write-Verbose "Install package $($_.LocalPackage) exists on the file system. Using locally cached copy for uninstall..."
						$UninstallSyntax = "$($_.UninstallString) /qn"
					} else {
						Write-Verbose "Install package $($_.LocalPackage) not found on file system..."
						if (!$PackageMsiFilePath) {
							Write-Verbose "No MSIName specified as param.  Searching current directory for MSI..."
							$LocalMsis = Get-ChildItem $WorkingDir -Filter '*.msi' | Select -first 1
							if (!$LocalMsis) {
								throw 'No MSIs found to support uninstall'
							} else {
								$PackageMsiFilePath = $LocalMsis.FullName
							}
						} elseif (!(Test-Path $PackageMsiFilePath)) {
							throw 'Package MSI needed but MSI specified does not exist in current directory'
						} else {
							##TODO: Check MSI's product name and version to ensure match
							#Write-Verbose "Checking $PackageMsiFilePath for matching product name and version..."
							#$MsiProperties = Get-Msi $PackageMsiFilePath
							#if (($MsiProperties['ProductName'] -notlike '*$ProductName*') -or ($MsiProperties['ProductVersion'] -ne $_.ProductVersion)) {
							#	throw 'Package MSI is not the same product as being uninstalled'
							#}
						}
						$UninstallSyntax = "/x `"$PackageMsiFilePath`" /qn"
					}
					$MsiExecArgs = $UninstallSyntax.ToLower().TrimStart('msiexec.exe ')
					Write-Verbose "Beginning uninstall using syntax: msiexec.exe $MsiExecArgs"
					Start-Process msiexec.exe -ArgumentList $MsiExecArgs -Wait -NoNewWindow
				} else {
					Write-Warning "Invalid uninstall string found for $ProductName..."
				}
			}
		} else {
			Write-Warning "$ProductName seems to already be uninstalled"
		}
	} catch {
		Write-Error $_.Exception.Message
	}
}

end {
	
}