# Get Interfaces

$IpConfig = Get-NetIPConfiguration

$IpConfig

Get-NetIPInterface -ifindex $IpConfig.InterfaceIndex | select ifIndex,ifAlias,Dhcp, AddressFamily

# Disable static address

$interface | Set-NetIPInterface -InterfaceAlias "Local Area Connection" -Dhcp Enabled 

# Set DHCP via netsh

netsh interface ip set dns "Local Area Connection" dhcp
netsh interface ip set address "Local Area Connection" dhcp
ipconfig /renew
ipconfig /registerdns

# Set DHCP via Powershell

$IPType = "IPv4"
$adapter = Get-NetAdapter | ? {$_.Status -eq "up"}
$interface = $adapter | Get-NetIPInterface -AddressFamily $IPType
If ($interface.Dhcp -eq "Disabled") {
 # Remove existing gateway
 If (($interface | Get-NetIPConfiguration).Ipv4DefaultGateway) {
 $interface | Remove-NetRoute -Confirm:$false
 }
 # Enable DHCP
 $interface | Set-NetIPInterface -DHCP Enabled
 # Configure the DNS Servers automatically
 $interface | Set-DnsClientServerAddress -ResetServerAddresses
}