# Delete all Spicework backups older than 30 days
$path = "D:\Spiceworks\backup"
$Daysback = "-30"

$CurrentDate = Get-Date
$DatetoDelete = $CurrentDate.AddDays($Daysback)
Get-ChildItem $Path | Where-Object { $_.LastWriteTime -lt $DatetoDelete } | Remove-Item