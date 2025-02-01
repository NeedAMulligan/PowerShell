

$CollID = "XYZ01234"

[string]$URI = "http://<server.domain.com>/OnevinnWS/OnevinnWS.asmx"
[string]$UsrName = "<DOMAIN\UserName>"
[string]$UsrPW = "<Password>"


$CompName = $env:COMPUTERNAME
$secpasswd = ConvertTo-SecureString "$UsrPW" -AsPlainText -Force
$mycreds = New-Object System.Management.Automation.PSCredential ("$UsrName", $secpasswd)
$zip = New-WebServiceProxy -uri $URI -Credential $mycreds

# Invoke Web Service

    try
    {
        $method = "AddToCollection"
        $zip."$method".Invoke($CompName, $null, $null, $CollID)
    }
    catch 
    {
        Write-Output "$_.Exception.Message"
        exit 1
    }

exit 0