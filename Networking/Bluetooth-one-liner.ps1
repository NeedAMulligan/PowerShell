$desktop = Get-HPBIOSSettingValue -Name "M.2 USB / Bluetooth"; $laptop = Get-HPBiosSettingValue -Name "Bluetooth"; if ($desktop -eq "Enable") {; Write-Output -message "Bluetooth is disabled"; Set-HPBIOSSettingValue -Name "M.2 USB / Bluetooth" -Value "Disable" } else { Write-Output -message "M.2 USb / Bluetooth module not found or is already disabled"; exit 5; }; if ($laptop -eq "Enable") {; Write-Output "Bluetooth is disabled"; Set-HPBIOSSettingValue -Name "Bluetooth" -Value "Disable";  } else {; Write-Output -message "Bluetooth not found or is already disabled"; exit 5; }

        
   
        
        
    
