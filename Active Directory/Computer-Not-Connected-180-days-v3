# Requires the Active Directory module to be installed.
# Run this script on a Domain Controller with administrative privileges.

$staleDays = 180
$currentDate = Get-Date
$outputPath = "C:\temp\computers-180-days.csv"

# Calculate the stale date outside the filter
$staleDate = $currentDate.AddDays(-$staleDays)

Write-Host "Searching for ENABLED computer objects that have not connected in more than $staleDays days..."

# Get all ENABLED computer objects that have been inactive for more than $staleDays days
$staleEnabledComputers = Get-ADComputer -Filter { (LastLogonTimestamp -lt $staleDate) -and (Enabled -eq $true) } -Properties LastLogonTimestamp, Description, Enabled | Where-Object { $_.LastLogonTimestamp -ne $null }

if ($staleEnabledComputers.Count -eq 0) {
    Write-Host "No stale, ENABLED computer objects found."
} else {
    Write-Host "Found $($staleEnabledComputers.Count) stale, ENABLED computer objects."

    # --- Export to CSV ---
    Write-Host "Exporting list of affected computers to $($outputPath)..."
    $staleEnabledComputers | Select-Object Name, DistinguishedName, @{Name='LastLogon';Expression={[DateTime]::FromFileTime($_.LastLogonTimestamp)}}, Description, Enabled | Export-Csv -Path $outputPath -NoTypeInformation -Force
    Write-Host "Export complete. Check $($outputPath) for the list."
    # --- End Export to CSV ---

    Write-Host "Processing stale computer objects..."

    foreach ($computer in $staleEnabledComputers) {
        $computerName = $computer.Name
        $lastLogon = [DateTime]::FromFileTime($computer.LastLogonTimestamp)
        $newDescription = "DISABLED - $($currentDate.ToString('yyyy-MM-dd'))"

        Write-Host "`nProcessing computer: $($computerName)"
        Write-Host "  Current Status: Enabled"
        Write-Host "  Last Logon: $($lastLogon)"

        try {
            # Update the computer description
            Set-ADComputer -Identity $computer.DistinguishedName -Description $newDescription -ErrorAction Stop
            Write-Host "  Successfully updated description to: '$newDescription'"

            # Disable the computer account
            Disable-ADAccount -Identity $computer.DistinguishedName -ErrorAction Stop
            Write-Host "  Successfully disabled computer account."

        } catch {
            Write-Warning "  Failed to process $($computerName). Error: $($_.Exception.Message)"
        }
    }
    Write-Host "`nScript execution complete."
}
