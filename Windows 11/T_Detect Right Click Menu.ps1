$registryPath = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"

Try {
    if(-NOT (Test-Path $registryPath))
    {
    Return $false };
    Exit 1

    if((Get-ItemPropertyValue $registryPath -Name '(default)' -errorAction SilentlyContinue) -eq '') {  } else { 
        return $false };
}
catch { 
    return $false }
return $true
Exit 0