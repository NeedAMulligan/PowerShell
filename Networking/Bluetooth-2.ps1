$return = Get-HPBIOSSettingValue -Name "Bluetooth"

if ($return -eq "Enable") {
        Set-HPBIOSSettingValue -Name "Bluetooth" -Value "Disable" | write-output "Bluetooth is disabled"
    } else {
        exit 5
    }
