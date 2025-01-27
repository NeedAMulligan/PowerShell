$Adobe = Get-WmiObject -Class Win32_Product | Where-Object{$_.Name -contains "Adobe Acrobat"}
$Adobe
if ($Adobe){ 
    Write-Output("Start Adobe Acrobat DC Uninstaller.")
    $Adobe.Uninstall()}
else {Write-Output("Adobe Acrobat DC is not present")}