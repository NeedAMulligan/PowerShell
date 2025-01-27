$MyPath = $env:temp
del $MyPath\lockout.txt
get-eventlog security -InstanceId 4740 -Newest 1 | fl | Out-File -Encoding "UTF8" $MyPath\lockout.txt
#get-eventlog security -InstanceId 4740 -newest 1 | fl > $env:temp\lockout.txt