Connect-ExchangeOnline -ShowProgress $true
Connect-AipService
Get-IRMConfiguration
Set-IRMConfiguration -AzureRMSLicensingEnabled $true
Enable-AipService
Get-AipService