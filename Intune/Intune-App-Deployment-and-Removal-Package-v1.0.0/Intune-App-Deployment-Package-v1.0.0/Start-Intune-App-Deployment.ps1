<#
.SYNOPSIS
    Launcher for the Resilient IT Intune application deployment package.
.DESCRIPTION
    Provides a technician menu for running Global or GCC High deployment scripts.
    The launcher does not modify the included deployment scripts.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PackageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

function Show-Menu {
    Clear-Host
    Write-Host 'Resilient IT - Intune App Deployment Package' -ForegroundColor Cyan
    Write-Host '=============================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'Global tenants' -ForegroundColor Yellow
    Write-Host '  1. Deploy iOS applications'
    Write-Host '  2. Deploy Android Enterprise work-profile applications'
    Write-Host '  3. Deploy Windows Company Portal'
    Write-Host '  4. Deploy Windows inbox-app removal'
    Write-Host ''
    Write-Host 'GCC High tenants' -ForegroundColor Yellow
    Write-Host '  5. Deploy iOS applications'
    Write-Host '  6. Deploy Android Enterprise work-profile applications'
    Write-Host '  7. Deploy Windows Company Portal'
    Write-Host '  8. Deploy Windows inbox-app removal'
    Write-Host ''
    Write-Host '  Q. Quit'
    Write-Host ''
}

function Invoke-PackageScript {
    param(
        [Parameter(Mandatory)]
        [string]$RelativePath,

        [switch]$PromptForTenantId
    )

    $scriptPath = Join-Path $PackageRoot $RelativePath
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "Required script was not found: $scriptPath"
    }

    $parameters = @{}
    if ($PromptForTenantId) {
        $tenantId = Read-Host 'Enter the GCC High tenant ID, or press Enter to use interactive tenant selection'
        if (-not [string]::IsNullOrWhiteSpace($tenantId)) {
            $parameters.TenantId = $tenantId.Trim()
        }
    }

    Write-Host ''
    Write-Host "Launching: $scriptPath" -ForegroundColor Green
    & $scriptPath @parameters
}

while ($true) {
    Show-Menu
    $selection = (Read-Host 'Select an option').Trim()

    try {
        switch ($selection.ToUpperInvariant()) {
            '1' { Invoke-PackageScript -RelativePath 'Global\Intune-Configure-iOS-Apps-Microsoft-Graph-PowerShell-v1.10.0.ps1' }
            '2' { Invoke-PackageScript -RelativePath 'Global\Intune-Configure-Android-Enterprise-Work-Profile-Apps-Global-v1.0.0.ps1' }
            '3' { Invoke-PackageScript -RelativePath 'Global\Intune-Deploy-Company-Portal-Global-v1.0.0.ps1' }
            '4' { Invoke-PackageScript -RelativePath 'Global\Deploy-Windows-Inbox-App-Removal-Intune-Global-v1.0.0.ps1' }
            '5' { Invoke-PackageScript -RelativePath 'GCCH\Intune-Configure-iOS-Apps-Microsoft-Graph-PowerShell-GCCH-v1.10.1.ps1' -PromptForTenantId }
            '6' { Invoke-PackageScript -RelativePath 'GCCH\Intune-Configure-Android-Enterprise-Work-Profile-Apps-GCCH-v1.0.0.ps1' -PromptForTenantId }
            '7' { Invoke-PackageScript -RelativePath 'GCCH\Intune-Deploy-Company-Portal-GCCH-v1.0.0.ps1' -PromptForTenantId }
            '8' { Invoke-PackageScript -RelativePath 'GCCH\Deploy-Windows-Inbox-App-Removal-Intune-GCCH-v1.0.0.ps1' -PromptForTenantId }
            'Q' { break }
            default {
                Write-Host 'Invalid selection.' -ForegroundColor Yellow
            }
        }
    }
    catch {
        Write-Host "Deployment failed: $($_.Exception.Message)" -ForegroundColor Red
    }

    if ($selection.ToUpperInvariant() -eq 'Q') {
        break
    }

    Write-Host ''
    Read-Host 'Press Enter to return to the menu' | Out-Null
}
