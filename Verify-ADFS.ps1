# Establish connection to Microsoft Graph
Connect-MgGraph -Scopes "Domain.Read.All"

# Define Log Path
$logPath = "c:\temp\DomainAuthStatus_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
if (!(Test-Path "c:\temp")) { New-Item -Path "c:\temp" -ItemType Directory }

# Get all domains and their authentication type
$domains = Get-MgDomain | Select-Object Id, AuthenticationType, IsVerified

# Log and Display results
$domains | Out-File -FilePath $logPath
$domains | Format-Table -AutoSize

Write-Host "Check complete. Results logged to $logPath" -ForegroundColor Cyan