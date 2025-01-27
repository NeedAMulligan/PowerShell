$dir = 'C:\temp\win11'
mkdir $dir
$webClient = New-Object System.Net.WebClient
$url = 'https://go.microsoft.com/fwlink/?linkid=2171764'
$file = "$($dir)\Windows11InstallationAssistant.exe"
$webClient.DownloadFile($url,$file)
Start-Process -FilePath $file -ArgumentList "/quiet /eula accept /auto upgrade /copylogs $dir"