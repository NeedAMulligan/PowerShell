import-module activedirectory
$allGroupsInfo    = Get-ADGroup -Filter * -Properties members
$numHeaders       = ($allGroupsInfo | Measure-Object).count
$numColSeparators = $numHeaders - 1
$numRows = 
$allGroupsInfo | 
foreach-object { $_.members | measure-object} | 
Sort-Object count -Descending | Select-Object -First 1 |
select -ExpandProperty count

$emptyRowToAdd  = ";" * $numColSeparators + "`r`n"
$emptyRowsToAdd = $emptyRowToAdd * $numRows
$hashHeaders    = $allGroupsInfo.name -join ";"
$csvMatrix =
@"
$hashheaders
$emptyRowsToAdd
"@ | ConvertFrom-Csv -Delimiter ";"

foreach ($group in ($csvMatrix | Get-Member | where-object { $_.membertype -eq 'noteproperty' }).name) {
    for ($i = 0 ; $i -lt (($allGroupsInfo | where-object {$_.name  -eq "$group"}).members | measure-object).count; $i++) {
        $csvMatrix[$i]."$group" = 
        ($allGroupsInfo | where-object {$_.name  -eq "$group"}).members[$i]
    }
}

$csvMatrix |
export-csv "C:\GroupReport.csv" -NoTypeInformation