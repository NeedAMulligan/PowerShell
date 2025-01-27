# Source Directories
$bsource = "$env:appdata\Brewpoint\Temp"
$asource = "$env:Appdata\Auto-Shopkeeper\Temp"

if((Get-ChildItem $bsource -force | Select-Object -First 1 | Measure-Object).Count -eq 0)
{
   # folder is empty
}

if(!(Get-ChildItem $bsource -force | Select-Object -First 1 | Measure-Object).Count -eq 0)
{
Remove-Item -Force $bsource\*
}
if((Get-ChildItem $asource -force | Select-Object -First 1 | Measure-Object).Count -eq 0)
{
   # folder is empty
}

if(!(Get-ChildItem $asource -force | Select-Object -First 1 | Measure-Object).Count -eq 0)
{
Remove-Item -Force $asource\*
}
