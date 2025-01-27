$return = Get-HPBIOSSettingValue -Name "M.2 USB / Bluetooth"

if ($return -eq "Enable") {
        Write-Output -message "Bluetooth is disabled"
        Set-HPBIOSSettingValue -Name "M.2 USB / Bluetooth" -Value "Disable" 
    } else {
        Write-Output Test
        exit 5
    }
