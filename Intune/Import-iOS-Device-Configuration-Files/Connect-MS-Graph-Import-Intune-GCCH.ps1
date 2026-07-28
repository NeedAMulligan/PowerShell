# 1. Connect to the USGov environment and explicitly set the Graph host context
Connect-MgGraph -Environment USGov -Scopes "DeviceManagementConfiguration.ReadWrite.All"
Update-MgGraphEnvironment -Environment USGov

# 2. Path to your folder and the US Gov Graph endpoint URL
$PolicyFolder = "C:\temp\IntunePolicies"
$Uri = "https://graph.microsoft.us/v1.0/deviceManagement/deviceConfigurations"

# Get all JSON files in the directory
$JsonFiles = Get-ChildItem -Path $PolicyFolder -Filter "*.json"

foreach ($File in $JsonFiles) {
    Write-Host "Processing policy: $($File.Name)" -ForegroundColor Cyan
    
    # Read and parse the JSON content
    $PolicyContent = Get-Content -Path $File.FullName -Raw | ConvertFrom-Json
    
    # Ensure tenant-specific or read-only properties are removed if present
    $PropertiesToRemove = @('id', 'createdDateTime', 'lastModifiedDateTime', 'version')
    foreach ($Prop in $PropertiesToRemove) {
        if ($PolicyContent.PSObject.Properties[$Prop]) {
            $PolicyContent.PSObject.Properties.Remove($Prop)
        }
    }

    # Convert back to JSON string
    $CleanedJsonBody = $PolicyContent | ConvertTo-Json -Depth 10

    try {
        # Send POST request to the GCC High endpoint
        Invoke-MgGraphRequest -Method POST -Uri $Uri -Body $CleanedJsonBody -ContentType "application/json"
        Write-Host "Successfully created: $($PolicyContent.displayName)" -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to create $($File.Name): $_" -ForegroundColor Red
    }
}