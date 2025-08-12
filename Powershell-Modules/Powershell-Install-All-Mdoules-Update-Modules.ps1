# Only proceed with updates if all installations were successful
if (-not $installFailed) {
    # Updating All Modules for All Users
    Write-Host "All installations completed successfully. Starting the update process..."

    # Loop through and update each installed module for all users
    foreach ($module in $modulesToInstall) {
        Write-Host "Updating module: $module..."
        try {
            Update-Module -Name $module -Force -Confirm:$false -ErrorAction Stop
            Write-Host "Successfully updated $module."
        }
        catch {
            Write-Error "Failed to update module $module. Error: $_"
            $installFailed = $true
        }
    }

    if (-not $installFailed) {
        Write-Host "All modules and the Windows feature have been successfully installed and updated. ✨"
    } else {
        Write-Warning "Some modules failed to update. Please review the errors above."
    }

} else {
    Write-Warning "Module installations failed. The update process was not started. Please review the errors above."
}
