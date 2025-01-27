$desktop = Get-HPBIOSSettingValue -Name "M.2 USB / Bluetooth" -ErrorAction SilentlyContinue
$laptop = Get-HPBiosSettingValue -Name "Bluetooth" -ErrorAction SilentlyContinue

if ($desktop -eq "Enable") {
        Write-Output "M.2 USB / Bluetooth is disabled"
        Set-HPBIOSSettingValue -Name "M.2 USB / Bluetooth" -Value "Disable" 
    } else {
        Write-Output "M.2 USB / Bluetooth adapter not found or is already disabled"
        exit 5
    }
if ($laptop -eq "Enable") {
        Write-Output "Bluetooth is disabled"
        Set-HPBIOSSettingValue -Name "Bluetooth" -Value "Disable"
    } else {
        Write-Output "Bluetooth adapter not found or is already disabled"
        exit 5
    }