$DaysInactive = 180
$time = (Get-Date).Adddays(-($DaysInactive))
Get-ADComputer -Filter {lastlogontimestamp -lt $time}  -Properties Name,OperatingSystem , lastlogontimestamp| Select Name,OperatingSystem ,@{N='lastlogontimestamp'; E={[DateTime]::FromFileTime($_.lastlogontimestamp)}} | export-csv c:\temp\oldcomputers.csv