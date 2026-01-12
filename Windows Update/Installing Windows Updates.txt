# Installing the PSWindowsUpdate Module #

Install-Module -Name PSWindowsUpdate -Force

# Confirm #

Get-Package -Name PSWindowsUpdate

# Set Execution Policy #

Set-ExecutionPolicy bypass

# Import the module #

Import-Module PSWindowsUpdate

# Check the current Windows Update client settings #

Get-WUSettings

# Scan and Download Windows Updates #

# Get-WindowsUpdate #

Get-WindowsUpdate -Download -AcceptAll

# Install Windows Updates #

Install-WindowsUpdate -MicrosoftUpdate -AcceptAll
