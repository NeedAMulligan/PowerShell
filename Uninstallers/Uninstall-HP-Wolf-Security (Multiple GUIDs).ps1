$msi = ((Get-Package | Where-Object { $_.Name -like "*HP Wolf Security*" }).fastpackagereference)

$oldVersions = @(

$msi

)

ForEach ($oldVersion In $oldVersions) {

$MSIArguments = @(

"/x"

"$oldVersion"

"/qn"

'REBOOT="ReallySuppress"'

)

Start-Process "msiexec.exe" -wait -ArgumentList $MSIArguments

}