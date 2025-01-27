
Write-Host -ForegroundColor Green "SECTION 1: Getting the list of users"

# Write Information to the screen
Write-Host -ForegroundColor yellow "Exporting the list of users to c:\users\users.csv"
# List the users in c:\users and export to the local profile for calling later
dir C:\Users | select Name | Export-Csv -Path C:\users\users.csv -NoTypeInformation
$list=Test-Path C:\users\users.csv



""
#########################
"-------------------"
Write-Host -ForegroundColor Green "SECTION 2: Beginning Script..."
"-------------------"
if ($list) {
    "-------------------"
    #Clear Mozilla Firefox Cache
    Write-Host -ForegroundColor Green "SECTION 3: Clearing Mozilla Firefox Caches"
    "-------------------"
    Write-Host -ForegroundColor yellow "Clearing Mozilla caches"
    Write-Host -ForegroundColor cyan
    Import-CSV -Path C:\users\users.csv -Header Name | foreach {
            Remove-Item -path C:\Users\$($_.Name)\AppData\Local\Mozilla\Firefox\Profiles\*.default\cache\* -Recurse -Force -EA SilentlyContinue -Verbose
            Remove-Item -path C:\Users\$($_.Name)\AppData\Local\Mozilla\Firefox\Profiles\*.default\cache\*.* -Recurse -Force -EA SilentlyContinue -Verbose
            Remove-Item -path C:\Users\$($_.Name)\AppData\Local\Mozilla\Firefox\Profiles\*.default\cache2\entries\* -Recurse -Force -EA SilentlyContinue -Verbose
            Remove-Item -path C:\Users\$($_.Name)\AppData\Local\Mozilla\Firefox\Profiles\*.default\cache2\entries\*.* -Recurse -Force -EA SilentlyContinue -Verbose
            Remove-Item -path C:\Users\$($_.Name)\AppData\Local\Mozilla\Firefox\Profiles\*.default\thumbnails\* -Recurse -Force -EA SilentlyContinue -Verbose
            Remove-Item -path C:\Users\$($_.Name)\AppData\Local\Mozilla\Firefox\Profiles\*.default\webappsstore.sqlite -Recurse -Force -EA SilentlyContinue -Verbose
            Remove-Item -path C:\Users\$($_.Name)\AppData\Local\Mozilla\Firefox\Profiles\*.default\chromeappsstore.sqlite -Recurse -Force -EA SilentlyContinue -Verbose
            }
    Write-Host -ForegroundColor yellow "Clearing Mozilla caches"
    Write-Host -ForegroundColor yellow "Done..."
    ""
    "-------------------"
    # Clear Google Chrome 
    Write-Host -ForegroundColor Green "SECTION 4: Clearing Google Chrome Caches"
    "-------------------"
    Write-Host -ForegroundColor yellow "Clearing Google caches"
    Write-Host -ForegroundColor cyan
    Import-CSV -Path C:\users\users.csv -Header Name | foreach {
            Remove-Item -path "C:\Users\$($_.Name)\AppData\Local\Google\Chrome\User Data\Default\Cache\*" -Recurse -Force -EA SilentlyContinue -Verbose
            Remove-Item -path "C:\Users\$($_.Name)\AppData\Local\Google\Chrome\User Data\Default\Cache\*.*" -Recurse -Force -EA SilentlyContinue -Verbose
            Remove-Item -path "C:\Users\$($_.Name)\AppData\Local\Google\Chrome\User Data\Default\Cache2\entries\*" -Recurse -Force -EA SilentlyContinue -Verbose
            Remove-Item -path "C:\Users\$($_.Name)\AppData\Local\Google\Chrome\User Data\Default\Media Cache" -Recurse -Force -EA SilentlyContinue -Verbose
            Remove-Item -path "C:\Users\$($_.Name)\AppData\Local\Google\Chrome\User Data\Profile 1\Media Cache" -Recurse -Force -EA SilentlyContinue -Verbose
            Remove-Item -path "C:\Users\$($_.Name)\AppData\Local\Google\Chrome\User Data\Profile 2\Media Cache" -Recurse -Force -EA SilentlyContinue -Verbose
            Remove-Item -path "C:\Users\$($_.Name)\AppData\Local\Google\Chrome\User Data\Profile 1\Cache\*" -Recurse -Force -EA SilentlyContinue -Verbose
            Remove-Item -path "C:\Users\$($_.Name)\AppData\Local\Google\Chrome\User Data\Profile 1\Cache\*.*" -Recurse -Force -EA SilentlyContinue -Verbose
            Remove-Item -path "C:\Users\$($_.Name)\AppData\Local\Google\Chrome\User Data\Profile 2\Cache\*" -Recurse -Force -EA SilentlyContinue -Verbose
            Remove-Item -path "C:\Users\$($_.Name)\AppData\Local\Google\Chrome\User Data\Profile 2\Cache\*.*" -Recurse -Force -EA SilentlyContinue -Verbose

            # UNComment the following line to remove the Chrome Write Font Cache too.
            # Remove-Item -path "C:\Users\$($_.Name)\AppData\Local\Google\Chrome\User Data\Default\ChromeDWriteFontCache" -Recurse -Force -EA SilentlyContinue -Verbose
            }

    "-------------------"
    # Clear Internet Explorer
    Write-Host -ForegroundColor Green "SECTION 5: Clearing Internet Explorer Caches"
     "-------------------"
    Write-Host -ForegroundColor yellow "Clearing  Internet Explorer caches"
     "-------------------"
    Write-Host -ForegroundColor cyan
    Import-CSV -Path C:\users\users.csv -Header Name | foreach {
	Remove-Item -path "C:\Users\$($_.Name)\AppData\Local\Microsoft\Windows\Temporary Internet Files\*" -Recurse -Force -EA SilentlyContinue -Verbose
	Remove-Item -path "C:\Windows\System32\config\systemprofile\AppData\Local\Microsoft\Windows\Temporary Internet Files\*" -Recurse -Force -EA SilentlyContinue -Verbose
	Remove-Item -path "C:\Windows\System32\config\systemprofile\AppData\Local\CrashDumps\*.dmp" -Recurse -Force -EA SilentlyContinue -Verbose

	Remove-Item -path "C:\Users\$($_.Name)\AppData\Local\Microsoft\Windows\INetCache\IE\*" -Recurse -Force -EA SilentlyContinue -Verbose
	Remove-Item -path "C:\Users\$($_.Name)\AppData\Local\Microsoft\Windows\INetCache\Low\IE\*" -Recurse -Force -EA SilentlyContinue -Verbose
	Remove-Item -path "C:\Users\$($_.Name)\AppData\Local\Microsoft\Windows\WER\*" -Recurse -Force -EA SilentlyContinue -Verbose
 	Remove-Item -path "C:\Users\$($_.Name)\AppData\Local\CrashDumps\*" -Recurse -Force -EA SilentlyContinue -Verbose
    	Remove-Item -path "C:\Users\$($_.Name)\AppData\Local\Microsoft\Windows\WebCache\*.*" -Recurse -Force -EA SilentlyContinue -Verbose
    	Remove-Item -path "C:\`$recycle.bin\" -Recurse -Force -EA SilentlyContinue -Verbose
    	Remove-Item -path "C:\Users\$($_.Name)\AppData\Local\Microsoft\Terminal Server Client\Cache\*.*" -Recurse -Force -EA SilentlyContinue -Verbose
            }
    

    "-------------------"
    # Clear Internet Explorer
    Write-Host -ForegroundColor Green "SECTION 6: Clearing Internet Explorer Recovery Sites"
     "-------------------"
    Write-Host -ForegroundColor yellow "Clearing Internet Explorer Recovery Sites"
     "-------------------"
    Write-Host -ForegroundColor cyan
    Import-CSV -Path C:\users\users.csv -Header Name | foreach {
	Remove-Item -path "C:\Users\$($_.Name)\AppData\Local\Microsoft\Internet Explorer\Recovery\Active\*" -Recurse -Force -EA SilentlyContinue -Verbose
	Remove-Item -path "C:\Users\$($_.Name)\AppData\Local\Microsoft\Internet Explorer\Recovery\Active\*.*" -Recurse -Force -EA SilentlyContinue -Verbose
            }
  

Write-Host -ForegroundColor Green "SECTION 7: Clearing MSOL Tracing Files"
     "-------------------"
    Write-Host -ForegroundColor yellow "Clearing MSOL Tracing"
    Write-Host -ForegroundColor cyan
    Import-CSV -Path C:\users\users.csv -Header Name | foreach {
            Remove-Item -path "C:\Users\$($_.Name)\AppData\Local\Microsoft\MSOIdentityCRL\Tracing\*" -Recurse -Force -EA SilentlyContinue -Verbose
            }

    Write-Host -ForegroundColor yellow "Done..."
    ""
   "-------------------"

    # Clear Windows Explorer Icon and Thumb
    Write-Host -ForegroundColor Green "SECTION 9: Clearing Windows Explorer Icon and Thumb cache Files"
     "-------------------"
    Write-Host -ForegroundColor yellow "Clearing Windows Explorer icon and thumb caches"
    Write-Host -ForegroundColor cyan
    Import-CSV -Path C:\users\users.csv -Header Name | foreach {
            Remove-Item -path "C:\Users\$($_.Name)\AppData\Local\Microsoft\Windows\Explorer\icon*.db" -Recurse -Force -EA SilentlyContinue -Verbose
            Remove-Item -path "C:\Users\$($_.Name)\AppData\Local\Microsoft\Windows\Explorer\thumb*.db" -Recurse -Force -EA SilentlyContinue -Verbose
            }

    # Clear GoToMeeting
    Write-Host -ForegroundColor Green "SECTION 11: Clearing Go to Meeting Temp Files"
     "-------------------"
    Write-Host -ForegroundColor yellow "Clearing Go to meeting Temp Files"
    Write-Host -ForegroundColor cyan
    Import-CSV -Path C:\users\users.csv -Header Name | foreach {
            Remove-Item -path "C:\Users\$($_.Name)\AppData\Local\GoToMeeting\*.*" -Recurse -Force -EA SilentlyContinue -Verbose
            Remove-Item -path "C:\Users\$($_.Name)\AppData\Local\GoToMeeting\*" -Recurse -Force -EA SilentlyContinue -Verbose
            }

  # Clear Chrome Code Cache
    Write-Host -ForegroundColor Green "SECTION 12: Clearing Chrome Code Cache Temp Files"
     "-------------------"
    Write-Host -ForegroundColor yellow "Clearing Chrome Code Cache Temp Files"
    Write-Host -ForegroundColor cyan
    Import-CSV -Path C:\users\users.csv -Header Name | foreach {
            Remove-Item -path "C:\Users\$($_.Name)\AppData\Local\Google\Chrome\User Data\Default\Code Cache\js\*.*" -Recurse -Force -EA SilentlyContinue -Verbose
            Remove-Item -path "C:\Users\$($_.Name)\AppData\Local\Google\Chrome\User Data\Default\Code Cache\js\*" -Recurse -Force -EA SilentlyContinue -Verbose
            Remove-Item -path "C:\Users\$($_.Name)\AppData\Local\Google\Chrome\User Data\Profile 1\Code Cache\js\*.*" -Recurse -Force -EA SilentlyContinue -Verbose
            Remove-Item -path "C:\Users\$($_.Name)\AppData\Local\Google\Chrome\User Data\Profile 1\Code Cache\js\*" -Recurse -Force -EA SilentlyContinue -Verbose
               }


    # Clear Windows regtrans-ms
    Write-Host -ForegroundColor Green "SECTION 13: Clearing Windows regtrans-ms and TM.blf Files"
     "-------------------"
    Write-Host -ForegroundColor yellow "Clearing Windows regtrans-ms and TM.blffiles"
    Write-Host -ForegroundColor cyan
   Import-CSV -Path C:\users\users.csv -Header Name | foreach {
            Remove-Item -path "C:\Users\$($_.Name)\*.TM.blf" -Recurse -Force -EA SilentlyContinue -Verbose
            Remove-Item -path "C:\Users\$($_.Name)\*.regtrans-ms" -Recurse -Force -EA SilentlyContinue -Verbose
            }

## start-sleep -s 20

    Write-Host -ForegroundColor yellow "Done..."
    ""
  "-------------------"
     Write-Host -ForegroundColor Green "All Tasks Done!"
    } else {
	Write-Host -ForegroundColor Yellow "Session Cancelled"	
	Exit
	}