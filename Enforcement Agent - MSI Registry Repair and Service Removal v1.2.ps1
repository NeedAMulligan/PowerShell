#Airlock Fix Enforcement Agent MSI Registry Keys & Service Removal v1.2 - Updated July 2025
#NOTE: This script requires SYSTEM rights to remove the airlockclient service and a stopcode (if used) populated in the script below. This script will exit if SYSTEM is not detected.
#You can remove this exit on line 31, however it is not recommended as the Airlock Client service removal can only be performed with SYSTEM privileges. Not removing the Service may prevent reinstallation.
#IMPORTANT: This script MUST be tested on a pilot group of computers first before wider deployment!!

#============================================SCRIPT PARAMS=============================================================================#
#Please place the stopcode here if in use, in quotes replacing $null, for example "password"
$global:stopcode = $null

#Currently this assumes the default install location(s) please replace them in your deployment if the path(s) are different
$global:airlockPath64 = "C:\Program Files (x86)\Airlock Digital\Airlock Digital Client\airlock.exe"
$global:airlockPath32 = "C:\Program Files\Airlock Digital\Airlock Digital Client\airlock.exe"

#======================================================================================================================================#

function Log {
    param ([string]$Message)
    Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message"
}

Log "Airlock Enforcement Agent MSI Registry Fix & Service / File Removal v1.1 - Updated June 2025" -ForegroundColor Cyan
Log "Please ensure you set a stopcode in the script if one is being used" -ForegroundColor Magenta

$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

Log "Current User: $currentUser"

if ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name -ne "NT AUTHORITY\SYSTEM") {

    Log "This script must be run as SYSTEM, exiting." -ForegroundColor Red
    exit
}

function AppCleanup {

#This checks to see if Airlock.exe exists.
if (Test-Path -Path $airlockPath64) {
    $airlockExe = $airlockPath64
} elseif (Test-Path -Path $airlockPath32) {
    $airlockExe = $airlockPath32
} else {
    $airlockExe = $null
}

#Check to see if the Airlock process is running, if it is try to stop it gracefully
if ($airlockExe) {

    $airlockExeversion=((Get-Item $airlockExe).VersionInfo).FileVersion
    Log "Airlock.exe: Exists on Disk v$airlockExeversion"

    $AirlockProcess = Get-Process "airlock" -ErrorAction SilentlyContinue
    if ($AirlockProcess -ne $null) {

        if ($stopcode)
        {
            Log "Airlock process is running, attempting to stop airlock nicely with a stopcode"
            Start-Process -FilePath $airlockExe -Wait -ArgumentList "-stop $stopcode"
        }
        else
        {
            Log "Airlock process is running, attempting to stop airlock nicely without a stopcode"
            Start-Process -FilePath $airlockExe -Wait -ArgumentList "-stop"
        }
    } else {
        Log "Airlock.exe: Not Running"
    }
} else {
    Log "Airlock.exe: Does not exist on disk"
}

Start-Sleep -Seconds 2

#This just ensures that the Airlock usermode process is no longer running
Log "Checking the Airlock usermode process has successfully stopped"
$AirlockProcess = Get-Process "airlock" -ErrorAction SilentlyContinue
if ($AirlockProcess -ne $null) {
    Log "Airlock process is still running, attempting to terminate it manually"
    taskkill.exe /f /im airlock.exe

    Start-Sleep -Seconds 2

    $AirlockProcess = Get-Process "airlock" -ErrorAction SilentlyContinue
    if ($AirlockProcess -ne $null) {
        #We don't want to continue processing if airlock usermode is still running and is unable to be stopped
        Log "Airlock.exe: Core process failed to be terminated, as a result this script will now exit"
        exit
    }
    Log "Airlock.exe: Terminated Successfully"

} else {
    Log "Airlock.exe: Not Running"
}

#Sometimes notifier may have started up due to an app startup registration, to ensure folder removal is successful we can remove it here
Log "Checking the Notifier usermode process(es) have successfully stopped"
$NotifierProcess = Get-Process "notifier" -ErrorAction SilentlyContinue
if ($NotifierProcess -ne $null){
    Log "Notifier process is still running, attempting to terminate it manually"
    taskkill.exe /f /im notifier.exe
    Start-Sleep -Seconds 2

    $NotifierProcess = $null
    $NotifierProcess = Get-Process "notifier" -ErrorAction SilentlyContinue
    if ($AirlockProcess -ne $null) {
        #We don't want to continue processing if airlock usermode is still running and is unable to be stopped
        Log "Notifier.exe: Failed Termination, this isn't critical however may indicate a larger issue"
    }
    else
    {
        Log "Notifier.exe: Terminated Successfully"
    }
}
else
{
    Log "Notifier.exe: Not Running"  
}

#Here we try and remove services just to make it easier for reinstall
Log "Checking if the AirlockClient and Airlock services exist"

$AirlockClientService = Get-Service -Name "AirlockClient" -ErrorAction SilentlyContinue
if ($AirlockClientService -ne $null)
{
    Log "Found AirlockClient service, status was: $($AirlockClientService.Status)"
    if ($AirlockClientService.Status -ne "Stopped") {
        Log "Trying to stop AirlockClient service"
        Stop-Service -Name "AirlockClient" -Force

        Start-Sleep -Seconds 2

        if ((Get-Service -Name "AirlockClient").Status -ne "Stopped") {
            Log "AirlockClient is still running even after a force stop, this script will now exit"
            exit
        }
    }

    Log "Trying to delete the AirlockClient service using the Windows Service Handler"
    $output = sc.exe delete AirlockClient
    if ($LASTEXITCODE -eq 0) {
        Log "Removed AirlockClient service successfully: $output"
    } 
    elseif ($LASTEXITCODE -eq 5){
        Log "ERROR removing AirlockClient service due to insufficient privileges. Only the SYSTEM user is permitted to modify the service due to the service's security descriptor. Please run this as SYSTEM if you want to fully clean up the agent. Current state could cause issues on reinstall (ExitCode $LASTEXITCODE): $output"    
    }
    else {
        Log "ERROR removing AirlockClient service (ExitCode $LASTEXITCODE): $output"
    }
}
else
{
    Log "AirlockClient Service: Not Found"
}

#What we want to do here is unload the filter driver to get ahead of any other installer teardowns. As long as the driver isn't attached to the airlock.exe usermode process this should work. If this hangs it could be due to an unload bug. Future improvements here could be to detect the function not returning.
Log "Airlock Driver: Attempting Unload using Filter Manager"
try {
    $output = fltmc unload airlock 2>&1

    if ($LASTEXITCODE -eq 0) {
        Log "Airlock Driver: Successfully Unloaded: $output "
    } else {
        Log "Airlock Driver: ERROR (ExitCode $LASTEXITCODE): $output"
    }

} catch {
    Log "EXCEPTION: $_"
}


#This tries to stop and remove the Airlock driver service
$AirlockDriverService = Get-Service -Name "Airlock" -ErrorAction SilentlyContinue
if ($AirlockDriverService -ne $null)
{
    Log "Airlock Driver Service: Found, status was: $($AirlockDriverService.Status)"
    if ($AirlockDriverService.Status -ne "Stopped") {
        Log "Trying to stop the Airlock driver service"
        Stop-Service -Name "Airlock" -Force

        Start-Sleep -Seconds 2

        if ((Get-Service -Name "Airlock").Status -ne "Stopped") {
            Log "Airlock Driver Service: Failed to Stop"
            return
        }
    }

    Log "Trying to delete Airlock driver service"
    $output = sc.exe delete Airlock
    if ($LASTEXITCODE -eq 0) {
        Log "Airlock Driver Service: Successfully Removed: $output"
    } else {
        Log "ERROR (ExitCode $LASTEXITCODE): $output"
    }
}
else
{
    #Do Nothing Here
}

#This tries to remove the driver from disk as long as the driver service doesn't exist
$AirlockDriverService = $null
$AirlockDriverService = Get-Service -Name "Airlock" -ErrorAction SilentlyContinue
Log "Confirming the Airlock Driver Service does not exist"
if ($AirlockDriverService -eq $null)
{
     Log "Airlock Driver Service: Not Found"
     #Since the service does not exist, we can try and remove the associated driver file from disk here 
     $windowsDir = $env:WINDIR
     $driverPath = Join-Path -Path $windowsDir -ChildPath "System32\drivers\airlock.sys"

     Log "Checking if airlock.sys exists"
     if (Test-Path -Path $driverPath) {

     $driverversion=((Get-Item $driverPath).VersionInfo).FileVersion
     Log "Airlock.sys: Exists on Disk v$driverversion, attempting deletion"
         try {
             Remove-Item -Path $driverPath

             if (Test-Path -Path $driverPath) {
                    Log "Airlock.sys: Deletion Failed"
                }
                else
                {
                    Log "Airlock.sys: Successfully Deleted"
                    $driverdoesnotexist = 1
                }
         } catch {
             Log "Airlock.sys: Deletion Failed: $_"
         }
     }
     else
     {
         Log "Airlock.sys: Not Found on Disk"
         $driverdoesnotexist = 1
     }

}
else
{
    Log "Airlock Driver Service: Service Still Registered"
}

#Check again to ensure the Airlock Client service is gone
$AirlockClientService = $null
$AirlockClientService = Get-Service -Name "AirlockClient" -ErrorAction SilentlyContinue

#If the driver service is gone, the driver is gone, the usermode service is gone and the airlock.exe still exists on disk we can delete the install folder

if (($driverdoesnotexist -eq 1) -and ($AirlockDriverService -eq $null) -and ($AirlockClientService -eq $null) -and ($airlockExe -ne $null)) {

Log "Removing Airlock Application Files"
if (Test-Path -Path $airlockExe) {
$airlockFolder = Split-Path -Path $airlockExe
Log "Airlock.exe binary found at $airlockExe, removing folder $airlockFolder"
if (Test-Path -Path $airlockFolder) {
    Remove-Item -Path $airlockFolder -Recurse -Force

    if (-not (Test-Path -Path $airlockFolder)) {
        Log "Folder $airlockFolder successfully removed"
    } else {
        Log "Failed to remove the Airlock install folder located at $airlockFolder"
    }
} else {
    Log "$airlockFolder does not exist"
}
}



}
}

#Call the function listed above
AppCleanup
 
#Firstly terminate all running msiexec services to make sure there aren't any stuck installers or existing deployments
Stop-Process -Name "msiexec" -Force -ErrorAction SilentlyContinue
 
#Get Product Registry Contents (HKLM)
$RegistryContents = Get-ChildItem -Path "HKLM:SOFTWARE\Classes\Installer\Products"  -ErrorVariable $getregistryitemserror
        if ($getregistryitemserror)
        {
            Write-Warning "Enumeration of the HKLM registry hive failed"  -ForegroundColor Red
            break
        }
 
#Get Product Registry Contents (HKCR)
New-PSDrive -PSProvider registry -Root HKEY_CLASSES_ROOT -Name HKCR -ErrorAction SilentlyContinue > $null
$RegistryContents2 = Get-ChildItem -Path "HKCR:Installer\Products"  -ErrorVariable $getregistryitemserror2
        if ($getregistryitemserror2)
        {
            Write-Warning "Enumeration of the HKCR registry hive failed"  -ForegroundColor Red
            break
        }
 
#Get Product Registry Contents (HKLM Wow64)
$RegistryContents3 = Get-ChildItem -Path "HKLM:SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall"  | Where-Object {$_.Property -like "DisplayName"} | Get-ItemProperty | Where-Object {$_.DisplayName -like "Airlock Digital Client"} -ErrorVariable $getregistryitemserror3
        if ($getregistryitemserror3)
        {
            Write-Warning "Enumeration of the HKLM registry hive failed"  -ForegroundColor Red
            break
        }
 
 
#Get Product Registry Contents (HKEY Users .DEFAULT)
New-PSDrive -PSProvider registry -Root HKEY_USERS -Name HKU -ErrorAction SilentlyContinue > $null

if (Test-Path "HKU:.DEFAULT\Software\Microsoft\Installer\Products") {

$RegistryContents4 = Get-ChildItem -Path "HKU:.DEFAULT\Software\Microsoft\Installer\Products"  | Where-Object {$_.Property -like "ProductName"} | Get-ItemProperty | Where-Object {$_.ProductName -like "Airlock Digital Client"} -ErrorVariable $getregistryitemserror4
        if ($getregistryitemserror4)
        {
            Write-Warning "Enumeration of the HKEY_USERS registry hive failed"  -ForegroundColor Red
            break
        }
}
 
#Get Product Registry Contents (HKLM Managed)
$RegistryContents5 = Get-ChildItem -Path "HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Installer" -Recurse  | Where-Object {$_.Property -like "ProductName"} | Get-ItemProperty | Where-Object {$_.ProductName -like "Airlock Digital Client"} -ErrorVariable $getregistryitemserror5
        if ($getregistryitemserror5)
        {
            Write-Warning "Enumeration of the HKLM registry hive failed"  -ForegroundColor Red
            break
        }
 
$KeyArray = @()
 
#Build a table of subkeys for HKLM
foreach($key in $RegistryContents.Name)
{
    $key = $key -replace 'HKEY_LOCAL_MACHINE\\', 'HKLM:'
 
    #Get the properties of the subkey
    $childkey = Get-ItemProperty -Path $key -ErrorVariable $getitempropertyfail
        if ($getitempropertyfail)
        {
            Write-Warning "Getting the subkey property failed"  -ForegroundColor Red
            break
        }
 
    #Match the Airlock Digital Client in the ProductName
    If ($childkey.ProductName -eq "Airlock Digital Client")
    {
 
        #Set Flag for Airlock  Found
        $AirlockFound = 1
 
        #Add to the Key Array
        $KeyArray += $key
    }
}
 
 
 
#Build a table of subkeys for HKCR
foreach($key2 in $RegistryContents2.Name)
{
    $key2 = $key2 -replace 'HKEY_CLASSES_ROOT\\', 'HKCR:'
 
    #Get the properties of the subkey
    $childkey2 = Get-ItemProperty -Path $key2 -ErrorVariable $getitempropertyfail2
        if ($getitempropertyfail2)
        {
            Write-Warning "Getting the subkey property failed"  -ForegroundColor Red
            break
        }
 
    #Match the Airlock Digital Client in the ProductName
    If ($childkey2.ProductName -eq "Airlock Digital Client")
    {
 
        #Set Flag for Airlock  Found
        $AirlockFound = 1
 
        #Add to the Key Array
        $KeyArray += $key2
    }
}
 
#Build a table of subkeys for HKLM UserData
foreach($key3 in $RegistryContents3.PSPath)
{
    $key3 = $key3 -replace 'Microsoft.PowerShell.Core\\Registry::', ''
    $key3 = $key3 -replace 'HKEY_LOCAL_MACHINE\\', 'HKLM:'
 
    #Add to the Key Array
    $KeyArray += $key3
 
    #Set Flag for Airlock  Found
    $AirlockFound = 1
   
}
 
#Build a table of subkeys for HKU
foreach($key4 in $RegistryContents4.PSPath)
{
    $key4 = $key4 -replace 'Microsoft.PowerShell.Core\\Registry::', ''
    $key4 = $key4 -replace 'HKEY_USERS\\', 'HKU:'
 
    #Add to the Key Array
    $KeyArray += $key4
 
    #Set Flag for Airlock  Found
    $AirlockFound = 1
   
}
 
#Build a table of subkeys for HKLM Managed
foreach($key5 in $RegistryContents5.PSPath)
{
    $key5 = $key5 -replace 'Microsoft.PowerShell.Core\\Registry::', ''
    $key5 = $key5 -replace 'HKEY_LOCAL_MACHINE\\', 'HKLM:'
 
    #Add to the Key Array
    $KeyArray += $key5
 
    #Set Flag for Airlock  Found
    $AirlockFound = 1
   
}

# Check for a notifier Startup Entry
$notifierregPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
$notifierValueName = "Airlock Notifier"

if (Get-ItemProperty -Path $notifierregPath -Name $notifierValueName -ErrorAction SilentlyContinue) {
    # Add the value path as a single string
    $KeyArray += "$notifierregPath\$notifierValueName"

    # Set Flag for Airlock Found
    $AirlockFound = 1

    Log "Airlock Client Agent RunOnce Registry Key Found" -ForegroundColor Green
}

 
 
If ($AirlockFound -eq "1")
{
 
    #Blank this out to make sure if it's run in the same session again it doesn't return a valid result
    $AirlockFound = $null

    #Make sure duplicate keys are not being removed
    $KeyArray = $KeyArray | select -Unique 

    #Really make sure the correct value is in here to triple check it has valid data
    foreach($todelete in $KeyArray)
    {
        #Delete the key and all subkeys
        Remove-Item -Path $todelete -Recurse -ErrorVariable $removeItemError
    }
 
    if ($removeItemError)
    {
       Write-Warning "Deletion of the Airlock Registry Keys failed"  -ForegroundColor Red
       break
    }
 
    sleep 1
 
    #Check the path after removal to confirm it is gone
 
    foreach($tocheck in $KeyArray)
    {
        if (Test-Path -Path $tocheck)
        {
            Log "Airlock key: $tocheck still present, something went wrong" -ForegroundColor Red
            $removalfailure = 1
        }
    }
 
    if ($removalfailure -ne "1")
    {
       Log "Airlock keys have been removed, please try installing the new Airlock Client again" -ForegroundColor Green
    }
 
    #Null out keys to be safe
    $key = $null
	$Name = $null
	$Value = $null
 
}
else
{
     Log "Airlock Digital Client Registry Keys were not found, please try installing the new Airlock Client Again" -ForegroundColor Yellow
}

$global:stopcode = $null