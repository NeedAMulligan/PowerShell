$Adobe = Get-WmiObject -Class Win32_Product | Where-Object{$_.Name -eq "Adobe Acrobat DC"}
$Adobe
if ($Adobe){ 
    Write-Output("Start Adobe Acrobat DC Uninstaller.")
    $Adobe.Uninstall()}
else {Write-Output("Adobe Acrobat DC is not present")}