# 1. Install the Microsoft Graph Intune Module if not present
if (!(Get-Module -ListAvailable -Name Microsoft.Graph.Intune)) {
    Write-Host "Installing Microsoft.Graph.Intune module..." -ForegroundColor Cyan
    Install-Module -Name Microsoft.Graph.Intune -AllowClobber -Force -Scope CurrentUser
}

# 2. Authenticate to Microsoft Graph
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MSGraph

# 3. Define Export Path
$ExportPath = "C:\Intune\iOS_Policy_Exports"
if (!(Test-Path $ExportPath)) { 
    New-Item -ItemType Directory -Path $ExportPath | Out-Null 
    Write-Host "Created export directory at $ExportPath" -ForegroundColor Green
}

# 4. Fetch all Device Configuration Profiles
Write-Host "Fetching device configurations..." -ForegroundColor Cyan
$AllProfiles = Get-DeviceConfiguration

# 5. Filter and Export Loop
$count = 0
foreach ($Profile in $AllProfiles) {
    # Check if the platform is specifically iOS/iPadOS
    # Note: Some profiles may use '@odata.type' to define platform
    if ($Profile.platformsSupported -eq "ios" -or $Profile.'@odata.type' -like "*ios*") {
        
        $count++
        $SafeName = $Profile.displayName -replace '[\\\/\:\*\?\"\<\>\|]', '_'
        $FullFilePath = Join-Path $ExportPath "$SafeName.json"

        # Sanitize the object for future import: Remove unique IDs and Read-Only timestamps
        $ExportObject = $Profile | Select-Object * -ExcludeProperty id, lastModifiedDateTime, createdDateTime, version

        # Convert to JSON and save
        $ExportObject | ConvertTo-Json -Depth 10 | Out-File $FullFilePath
        
        Write-Host "[$count] Exported: $($Profile.displayName)" -ForegroundColor Green
    }
}

if ($count -eq 0) {
    Write-Warning "No iOS configuration policies were found in this tenant."
} else {
    Write-Host "`nSuccess: $count iOS policies exported to $ExportPath" -ForegroundColor White -BackgroundColor DarkGreen
}