# Check for the SSO Computer Account
$ssoAccount = Get-ADComputer -Filter "Name -eq 'AZUREADSSOACC'" -Properties ServicePrincipalNames, PasswordLastSet

if ($ssoAccount) {
    Write-Host "Account Found: $($ssoAccount.DistinguishedName)" -ForegroundColor Green
    Write-Host "Last Password Change: $($ssoAccount.PasswordLastSet)" -ForegroundColor Cyan
    Write-Host "SPNs configured:"
    $ssoAccount.ServicePrincipalNames | ForEach-Object { Write-Host " - $_" }
} else {
    Write-Error "AZUREADSSOACC not found! You must run the 'Enable-AzureADSSOForest' command from your Entra Connect server first."
}