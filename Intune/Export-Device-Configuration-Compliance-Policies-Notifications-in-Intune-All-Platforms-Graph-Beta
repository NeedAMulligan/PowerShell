<#
.SYNOPSIS
    Intune Configuration and Policy Export Tool.

.DESCRIPTION
    This script connects to the Microsoft Graph API to export Intune policies across all platforms 
    (Windows, macOS, iOS, Android, Linux). It creates a timestamped, tenant-named backup folder 
    containing JSON exports organized by Platform and Policy Type.

    The script exports:
    - Settings Catalog Policies
    - Device Configuration Templates (Administrative Templates, Custom, etc.)
    - Device Compliance Policies
    - App Protection Policies (MAM)
    - Global Device Categories

.PREREQUISITES
    - Microsoft.Graph PowerShell Module
    - Permissions: DeviceManagementConfiguration.Read.All, DeviceManagementApps.Read.All, 
                   DeviceManagementManagedDevices.Read.All, Organization.Read.All

.OUTPUTS
    - C:\temp\<TenantName>_Intune-Policies_<Timestamp>\
    - Export_Summary.txt (A verification log and error report)
#>

# 1. Connect with necessary scopes
$Scopes = @(
    "DeviceManagementConfiguration.Read.All", 
    "DeviceManagementApps.Read.All", 
    "DeviceManagementManagedDevices.Read.All", 
    "Organization.Read.All"
)
Connect-MgGraph -TenantId "rogercogcc.onmicrosoft.com" -Scopes $Scopes

# 2. Get Tenant Name for folder prefix
Write-Host "Identifying Tenant..." -ForegroundColor Cyan
$Org = Get-MgOrganization | Select-Object -First 1
$TenantName = $Org.DisplayName -replace '[\\\/\:\*\?\"\<\>\| ]', ''

# 3. Setup Timestamped Root Directory in C:\temp
$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
$RootPath = "C:\temp\$($TenantName)_Intune-Policies_$Timestamp"

if (!(Test-Path "C:\temp")) { New-Item -ItemType Directory -Path "C:\temp" | Out-Null }
if (!(Test-Path $RootPath)) { New-Item -ItemType Directory -Path $RootPath | Out-Null }

# 4. Initialize Counters and Error Logs
$Count_SettingsCatalog = 0
$Count_DeviceConfig = 0
$Count_Compliance = 0
$Count_MAM = 0
$Count_Global = 0
$FailedExports = @()

# 5. Pre-fetch all data from Graph (Beta)
Write-Host "Downloading policy data..." -ForegroundColor Cyan
$AllSettingsCatalog = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies").Value
$AllPlatformConfigs = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations").Value
$AllCompliance      = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies").Value
$AllMAM             = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceAppManagement/managedAppPolicies").Value

$Platforms = @("Windows", "macOS", "Android", "iOS", "Linux")

foreach ($Platform in $Platforms) {
    Write-Host "`n>>> Processing Platform: $Platform" -ForegroundColor White -BackgroundColor DarkBlue
    
    $BaseDir   = Join-Path $RootPath $Platform
    $ConfigDir = Join-Path $BaseDir "Configuration"
    $CompDir   = Join-Path $BaseDir "Compliance"
    $MamDir    = Join-Path $BaseDir "MAM"

    # Create subfolder structure
    $Paths = @($ConfigDir, $CompDir, $MamDir)
    foreach ($Path in $Paths) { if (!(Test-Path $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null } }

    # --- A. Configuration (Settings Catalog & Device Config) ---
    $FilteredSettings = $AllSettingsCatalog | Where-Object { $_.platforms -match $Platform }
    foreach ($P in $FilteredSettings) {
        try {
            $FullPolicy = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($P.id)?`$expand=settings"
            $SafeName = $P.name -replace '[\\\/\:\*\?\"\<\>\|]', '_'
            $FullPolicy | ConvertTo-Json -Depth 10 | Out-File -LiteralPath "$ConfigDir\SettingsCatalog_$SafeName.json"
            $Count_SettingsCatalog++
        } catch { $FailedExports += "Config (Catalog): $($P.name) - $($_.Exception.Message)" }
    }
    $FilteredPlatform = $AllPlatformConfigs | Where-Object { $_.'@odata.type' -like "*$Platform*" }
    foreach ($PC in $FilteredPlatform) {
        try {
            $SafeName = $PC.displayName -replace '[\\\/\:\*\?\"\<\>\|]', '_'
            $PC | ConvertTo-Json -Depth 10 | Out-File -LiteralPath "$ConfigDir\DeviceConfig_$SafeName.json"
            $Count_DeviceConfig++
        } catch { $FailedExports += "Config (Platform): $($PC.displayName) - $($_.Exception.Message)" }
    }

    # --- B. Compliance ---
    $FilteredComp = $AllCompliance | Where-Object { $_.'@odata.type' -like "*$Platform*" }
    foreach ($C in $FilteredComp) {
        try {
            $SafeName = $C.displayName -replace '[\\\/\:\*\?\"\<\>\|]', '_'
            $C | ConvertTo-Json -Depth 10 | Out-File -LiteralPath "$CompDir\Compliance_$SafeName.json"
            $Count_Compliance++
        } catch { $FailedExports += "Compliance: $($C.displayName) - $($_.Exception.Message)" }
    }

    # --- C. MAM ---
    $FilteredMAM = $AllMAM | Where-Object { $_.'@odata.type' -like "*$Platform*" -or $_.displayName -like "*$Platform*" }
    foreach ($M in $FilteredMAM) {
        try {
            $SafeName = $M.displayName -replace '[\\\/\:\*\?\"\<\>\|]', '_'
            $M | ConvertTo-Json -Depth 10 | Out-File -LiteralPath "$MamDir\MAM_$SafeName.json"
            $Count_MAM++
        } catch { $FailedExports += "MAM: $($M.displayName) - $($_.Exception.Message)" }
    }
}

# 6. Global Items
try {
    Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceCategories" | 
        Select-Object -ExpandProperty Value | ConvertTo-Json | Out-File -LiteralPath "$RootPath\Global_DeviceCategories.json"
    $Count_Global++
} catch { $FailedExports += "Global Items: Device Categories" }

# 7. Summary and Verification Log
$Total = $Count_SettingsCatalog + $Count_DeviceConfig + $Count_Compliance + $Count_MAM + $Count_Global
$SummaryText = @"
INTUNE EXPORT SUMMARY
Tenant:   $($Org.DisplayName)
Date:     $(Get-Date)
Location: $RootPath
--------------------------------------
Settings Catalog Policies: $Count_SettingsCatalog
Device Config (Templates): $Count_DeviceConfig
Compliance Policies:       $Count_Compliance
MAM (App Protection):      $Count_MAM
Global Items:              $Count_Global
--------------------------------------
TOTAL FILES EXPORTED:      $Total

FAILED EXPORTS:
"@

if ($FailedExports.Count -eq 0) {
    $SummaryText += "`nNone - All policies exported successfully."
} else {
    foreach ($Fail in $FailedExports) { $SummaryText += "`n- $Fail" }
}

$SummaryText | Out-File -LiteralPath "$RootPath\Export_Summary.txt"

Write-Host "`n==============================================="
Write-Host "EXPORT COMPLETE - $Total FILES SAVED TO C:\TEMP" -ForegroundColor White -BackgroundColor DarkGreen
Write-Host "Verification file created at: $RootPath\Export_Summary.txt" -ForegroundColor Gray
