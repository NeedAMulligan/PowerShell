# 1. Enable System Location Services (Prerequisite for Auto Time Zone)
$consentPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location"
if (-not (Test-Path $consentPath)) {
    New-Item -Path $consentPath -Force | Out-Null
}
Set-ItemProperty -Path $consentPath -Name "Value" -Value "Allow" -Type String

# 2. Set Auto Time Zone Service (tzautoupdate) to Automatic Startup
$tzRegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\tzautoupdate"
if (Test-Path $tzRegistryPath) {
    Set-ItemProperty -Path $tzRegistryPath -Name "Start" -Value 2 -Type DWord
}

# 3. Enable and Start the Service via PowerShell Cmdlets
Set-Service -Name "tzautoupdate" -StartupType Automatic
Start-Service -Name "tzautoupdate" -ErrorAction SilentlyContinue

# 4. Verify Service Status
$service = Get-Service -Name "tzautoupdate"
Write-Output "tzautoupdate service status: $($service.Status)"