# Array to list all installed Software details

$InstalledSoftware = New-Object System.Collections.ArrayList
 
# Get all 32-Bit versions installed by querying the registry

$32BitApps = Get-ChildItem "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall" | Get-ItemProperty | Where-Object {$_.DisplayName -ne $null} | Select-Object DisplayName, DisplayVersion, Publisher, InstallDate
$32BitApps | ForEach-Object { 
    $InstalledSoftware.Add([PSCustomObject]@{
        ApplicationName     = $_.DisplayName
        Version = if ($null -eq $_.DisplayVersion -or [string]::Empty -eq $_.DisplayVersion) { "N/A" } else { $_.DisplayVersion }
        Publisher      = if ($null -eq $_.Publisher -or [string]::Empty -eq $_.Publisher) { "N/A" } else { $_.Publisher }
        InstallDate = if ($null -eq $_.InstallDate -or [string]::Empty -eq $_.InstallDate) { "N/A" } else { $_.InstallDate }
        Scope = "32-Bit"
    }) | Out-Null
}
  
# Get all 64 bit versions installed by querying the registry

$64BitApps = Get-ChildItem "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall" | Get-ItemProperty | Where-Object {$_.DisplayName -ne $null} | Select-Object DisplayName, DisplayVersion, Publisher, InstallDate
$64BitApps | ForEach-Object { 
   $InstalledSoftware.Add([PSCustomObject]@{
        ApplicationName     = $_.DisplayName
        Version = if ($null -eq $_.DisplayVersion -or [string]::Empty -eq $_.DisplayVersion) { "N/A" } else { $_.DisplayVersion }
        Publisher      = if ($null -eq $_.Publisher -or [string]::Empty -eq $_.Publisher) { "N/A" } else { $_.Publisher }
        InstallDate = if ($null -eq $_.InstallDate -or [string]::Empty -eq $_.InstallDate) { "N/A" } else { $_.InstallDate }
        Scope = "64-Bit"
    })| Out-Null
}

# Export all installed software to a CSV file
$InstalledSoftware | Sort-Object -Property ApplicationName, Version, Publisher, InstallDate, Scope -Unique | Export-csv -NoTypeInformation "YOURPATH\SoftwareList.csv"
