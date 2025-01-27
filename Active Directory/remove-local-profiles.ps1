Remove local profiles

 

First step:

Find User folder matched with their Registry SID <= use if folder is present in the files system

 

Get-WMIObject -class Win32_UserProfile | fl LocalPath, SID

 

Second step, remove the profile:

 

$SIDS = "S-1-5-21-902708724-930761740-538272213-6721","S-1-5-21-2902418489-567235417-802846432-1005","<each other SID>"

 

foreach ($SID in $SIDS) {
Get-WMIObject -class Win32_UserProfile | Where -Property SID -EQ $SID | Remove-WmiObject
}

 

==================