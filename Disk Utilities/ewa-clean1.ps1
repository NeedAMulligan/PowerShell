# Calcuate free space percentage

Get-CimInstance -Class CIM_LogicalDisk | Select-Object @{Name="Size(GB)";Expression={$_.size/1gb}}, @{Name="Free Space(GB)";Expression={$_.freespace/1gb}}, @{Name="Free (%)";Expression={"{0,6:P0}" -f(($_.freespace/1gb) / ($_.size/1gb))}}, DeviceID, DriveType | Where-Object DriveType -EQ '3'

$confirmation = Read-Host "Are you ready? [y/n]"
while($confirmation -ne "y")
{
    if ($confirmation -eq 'n') {exit}
    $confirmation = Read-Host "Are you ready? [y/n]"
}

# Remove Windows Update Software Distribution Folder

Write-Host -ForegroundColor Green "Stopping Windows Update Services"
Get-Service -Name wuauserv | Stop-Service -Force -Verbose
Write-Host -ForegroundColor Green "Deleting Software Distribution Folder"
Remove-Item -Path C:\Windows\SoftwareDistribution -Recurse -Force -Verbose
Write-Host -ForegroundColor Green "Starting Windows Update Services"
Get-Service -Name wuauserv | Start-Service -Verbose

# Delete temp files and logs 

Write-Host -ForegroundColor Red "Clearing files from %appdata%\local\temp (Older than 24 hours)"
Get-ChildItem "C:\users\*\AppData\Local\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { ($_.CreationTime -lt $(Get-Date).AddDays(-1))} | remove-item -force -Verbose -recurse -ErrorAction SilentlyContinue

Write-Host -ForegroundColor Red "Clearing files from C:\Windows\Temp (Older than 24 hours)"
Get-ChildItem "C:\Windows\Temp" -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { ($_.CreationTime -lt $(Get-Date).AddDays(-1))} | remove-item -force -Verbose -recurse -ErrorAction SilentlyContinue

Write-Host -ForegroundColor Red "Clearing CBS log files"
Remove-Item -path "C:\Windows\Logs\CBS\*" -Recurse -Force -ErrorAction SilentlyContinue -Verbose

Write-Host -ForegroundColor Red "Clearing DISM log files"
Remove-Item -path "C:\Windows\Logs\DISM\*" -Recurse -Force -ErrorAction SilentlyContinue -Verbose

Write-Host -ForegroundColor Red "Clearing Pre-fetch Files"
Get-ChildItem "C:\Windows\Prefetch\*" -Recurse -Force -Verbose -ErrorAction SilentlyContinue | Remove-Item -Force -Verbose -Recurse -ErrorAction SilentlyContinue

Write-Host -ForegroundColor Red "Clearing IIS Logs"
Get-ChildItem "C:\inetpub\logs\LogFiles\*" -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Force -Verbose -Recurse -ErrorAction SilentlyContinue

Write-Host -ForegroundColor Red "Clearing Temporary Internet Files"
Get-ChildItem "C:\users\*\AppData\Local\Microsoft\Windows\Temporary Internet Files\*" ` -Recurse -Force -Verbose -ErrorAction SilentlyContinue | Remove-Item -force -recurse -ErrorAction SilentlyContinue

# Clear Microsoft Teams cache

Write-Host -ForegroundColor Green "Clearing Microsoft Teams cache"
Get-ChildItem "C:\Users\*\AppData\Roaming\Microsoft\Teams\Cache\f_*" -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { ($_.CreationTime -lt $(Get-Date).AddDays(-1))} | Remove-Item -force -Verbose -recurse -ErrorAction SilentlyContinue

# Clear IE Cache

Write-Host -ForegroundColor Green "Clearing Internet Explorer Cache (Older than 24 hours)"
Get-ChildItem "C:\users\*\AppData\Local\Microsoft\Windows\INetCache\*" -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { ($_.CreationTime -lt $(Get-Date).AddDays(-1))} | Remove-Item -force -Verbose -recurse -ErrorAction SilentlyContinue

# Clear Google Chrome Cache

Write-Host -ForegroundColor Green "Clearing Google Chrome Cache (Older than 24 hours)"
Get-ChildItem "C:\Users\*\AppData\Local\Google\Chrome\User Data\Default\cache\*" -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { ($_.CreationTime -lt $(Get-Date).AddDays(-1))} | Remove-Item -force -Verbose -recurse -ErrorAction SilentlyContinue

# Clear Mozilla Firefox Cache

Write-Host -ForegroundColor Green "Clearing Mozilla Firefox Cache (Older than 24 hours)"
Get-ChildItem "C:\Users\*\AppData\Local\Mozilla\Firefox\Profiles\*.default\cache2\entries\*" -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { ($_.CreationTime -lt $(Get-Date).AddDays(-1))} | Remove-Item -force -Verbose -recurse -ErrorAction SilentlyContinue

# Clear Microsoft Edge Cache

Write-Host -ForegroundColor Green "Clearing Microsoft Edge Cache (Older than 24 hours)"
Get-ChildItem "C:\Users\*\AppData\Local\Microsoft\Edge\User Data\Default\Cache\*" -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { ($_.CreationTime -lt $(Get-Date).AddDays(-1))} | Remove-Item -force -Verbose -recurse -ErrorAction SilentlyContinue

# Clear Microsoft Office cache

Write-Host -ForegroundColor Green "Clearing Microsoft Office Cache (Older than 24 hours)"
Get-ChildItem "C:\Users\*\AppData\Local\Microsoft\Office\16.0\OfficeFileCache\*" -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { ($_.CreationTime -lt $(Get-Date).AddDays(-1))} | Remove-Item -force -Verbose -recurse -ErrorAction SilentlyContinue

# Clear Windows Recent Destinations

Write-Host -ForegroundColor Green "Clearing Windows Recent Destinations (Older than 24 hours)"
Get-ChildItem "C:\Users\*\AppData\Roaming\Microsoft\Windows\Recent\AutomaticDestinations\*" -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { ($_.CreationTime -lt $(Get-Date).AddDays(-1))} | Remove-Item -force -Verbose -recurse -ErrorAction SilentlyContinue

===============
# Empty Recycle bin

Write-Host -ForegroundColor Red "Emptying Recycle Bin"

Get-ChildItem "c:\`$Recycle.Bin\*\`$*" -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -force -Verbose -recurse -ErrorAction SilentlyContinue

Get-ChildItem "d:\`$Recycle.Bin\*\`$*" -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -force -Verbose -recurse -ErrorAction SilentlyContinue

Get-ChildItem "e:\`$Recycle.Bin\*\`$*" -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -force -Verbose -recurse -ErrorAction SilentlyContinue

Get-ChildItem "f:\`$Recycle.Bin\*\`$*" -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -force -Verbose -recurse -ErrorAction SilentlyContinue

Get-ChildItem "z:\`$Recycle.Bin\*\`$*" -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -force -Verbose -recurse -ErrorAction SilentlyContinue

# DISM Cleanup

Write-Host -ForegroundColor Green "Starting Component Store Cleanup"
Dism.exe /online /Cleanup-Image /StartComponentCleanup
Dism.exe /online /Cleanup-Image /StartComponentCleanup /ResetBase
Dism.exe /online /Cleanup-Image /SPSuperseded