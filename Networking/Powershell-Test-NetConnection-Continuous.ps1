do
{
    TEST-NETCONNECTION IP.ADDRESS -port 443
    Start-Sleep -Seconds 1
}
until([Console]::KeyAvailable)