# Stop services that sync Insider settings
Stop-Service -Name "wuauserv" -Force -ErrorAction SilentlyContinue
Stop-Service -Name "wisvc" -Force -ErrorAction SilentlyContinue

# Disable Windows Insider Service
Set-Service -Name "wisvc" -StartupType Disabled

# Purge Registry entries (HKLM + Current User)
$Paths = @(
    "HKLM:\SOFTWARE\Microsoft\WindowsSelfHost",
    "HKCU:\SOFTWARE\Microsoft\WindowsSelfHost"
)
foreach ($Path in $Paths) {
    if (Test-Path $Path) {
        Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Enforce Group Policy / Registry block against Insider builds
$PolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PreviewBuilds"
if (-not (Test-Path $PolicyPath)) {
    New-Item -Path $PolicyPath -Force | Out-Null
}
Set-ItemProperty -Path $PolicyPath -Name "AllowBuildPreview" -Value 0 -Type DWord

# Restart Windows Update Service
Start-Service -Name "wuauserv" -ErrorAction SilentlyContinue

Write-Host "Insider Program settings purged and blocked. Please reboot your PC." -ForegroundColor Green