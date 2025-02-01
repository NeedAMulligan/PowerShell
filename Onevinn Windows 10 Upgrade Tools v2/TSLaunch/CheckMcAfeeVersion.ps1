
$MinVersion = [Version]"10.5.3"


if(Test-Path -Path 'HKLM:\SOFTWARE\McAfee\Endpoint\Common') {

    $InstalledVersion = [Version](Get-ItemProperty -Path 'HKLM:\SOFTWARE\McAfee\Endpoint\Common' -Name 'ProductVersion').ProductVersion
     
    if($InstalledVersion.CompareTo($MinVersion) -ge 0) {
        
        Write-Output "Custom script detected McAfee Endpoint version: $($InstalledVersion.ToString())" ; exit 0
    }
    else {
        Write-Warning "Custom script detected McAfee Endpoint version: $($InstalledVersion.ToString()) - Aborting" ; exit 1
    }
}

Write-Warning "Custom script didn't detected McAfee Endpoint" ; exit 0