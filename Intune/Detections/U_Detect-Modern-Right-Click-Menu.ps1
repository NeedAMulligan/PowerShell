#Revert to classic right click menu
$registryPath = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
$name="(default)"
$value=''
$errMsg = $_.ExceptionMessage

If (!(Test-Path $registryPath))
{
Write-Output "Not Compliant - Modern Menu Set - Remediation Required"
Write-Host $errMsg
Exit 1
}


$check=(Get-ItemProperty -path $registryPath -name $name -ErrorAction SilentlyContinue).$name
if ($check -eq $value){
Write-Output "Compliant - Classic Menu set - No Remediation Required"
Write-Host $errMsg
Exit 0
}

else {
Write-Output "Not Compliant - Registry Value Could Not Be Read - Remediation Required"
Write-Host $errMsg
Exit 1
}