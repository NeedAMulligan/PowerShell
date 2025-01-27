#Revert to classic right click menu
$registryPath = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
$name="(default)"
$value=''
$errMsg = $_.ExceptionMessage

If (!(Test-Path $registryPath))
{
New-Item -Path $registryPath -ErrorAction SilentlyContinue
}

if (!(Get-ItemProperty -Path $registryPath -Name $name -ErrorAction SilentlyContinue))
{
New-ItemProperty -Path $registryPath -Name $name -Value $value -PropertyType String -ErrorAction SilentlyContinue
Write-Output "Remediation Complete"
Write-Host $errMsg
exit 0
}

Set-ItemProperty -Path $registryPath -Name $name -Value $value -ErrorAction SilentlyContinue
Write-Output "Remediation Complete"
Write-Host $errMsg
exit 0