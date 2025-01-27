#Set-ExecutionPolicy Bypass

$ServerAddress = "vpn.domain.com"

$ConnectionName = "VPN"

$PresharedKey = "pre-sharedkey"

$Destination = "0.0.0.0/0"

Add-VpnConnection -Name "$ConnectionName" -ServerAddress "$ServerAddress" -TunnelType L2tp -L2tpPsk "$PresharedKey" -AuthenticationMethod Pap -Force -AllUserConnection -RememberCredential -EncryptionLevel Optional