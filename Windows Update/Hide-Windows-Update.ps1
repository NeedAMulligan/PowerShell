Set-ExecutionPolicy bypass
Install-Module PSWindowsUpdate
Get-WindowsUpdate

ComputerName Status     KB          Size Title
------------ ------     --          ---- -----
HRN-5CD30... -------                20KB Intel Corporation - Extension - 1.1122.615.2
HRN-5CD30... -------                16MB Intel Corporation - SoftwareComponent - 1.1122.713.2

Hide-WindowsUpdate -Title "Intel Corporation - SoftwareComponent - 1.1122.713.2"
Hide-WindowsUpdate -Title "Intel Corporation - Display - 31.0.101.4887"

Get-WindowsUpdate

ComputerName Status     KB          Size Title
------------ ------     --          ---- -----
HRN-5CD30... -------                20KB Intel Corporation - Extension - 1.1122.615.2

UnInstall-Module PSWindowsUpdate
Set-ExecutionPolicy Default
