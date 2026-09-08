<#
.SYNOPSIS
    Completely disables hibernation, deletes hiberfil.sys, and locks down registry settings.
.DESCRIPTION
    This script checks for administrator rights, disables hibernation via powercfg,
    and sets HibernateEnabled and HibernateEnabledDefault to 0 in the registry.
#>

# Ensure running as Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as an Administrator."
    exit 1
}

Write-Host "Disabling hibernation and removing hiberfil.sys..." -ForegroundColor Cyan
try {
    $result = powercfg /hibernate off 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "powercfg failed: $result"
    }
    Write-Host "Hibernation successfully disabled." -ForegroundColor Green
}
catch {
    Write-Error "Failed to disable hibernation: $_"
    exit 1
}

Write-Host "Locking down registry configurations..." -ForegroundColor Cyan
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Power"
$settings = @("HibernateEnabled", "HibernateEnabledDefault")

foreach ($setting in $settings) {
    try {
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        Set-ItemProperty -Path $regPath -Name $setting -Value 0 -Type DWord -ErrorAction Stop
        Write-Host "Successfully configured registry key: $setting = 0" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to set registry key $setting : $_"
    }
}

Write-Host "Hibernation removal and lockdown completed successfully." -ForegroundColor Cyan