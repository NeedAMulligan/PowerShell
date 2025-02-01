'JRE_Updater 
'Updates and optionally deploys or removes Java Runtime 
'Last Update: 11/3/2016 
'By Kevin Denham (kevin.denham@gmail.com) 
' Release info/Version notes @ https://gallery.technet.microsoft.com/scriptcenter/Java-Automatic-and-Update-a053d98c
'=================   Options   ================================== 
'Download=0 if this is a client that is 'not' downloading 
Download=1
'ModifyJRE=0 if this is a host that is 'only' downloading 
Modify=1 
 
'Location for downloaded files.  Example: FileStore="\\Server\SharedFolder\" 
'Leaving FileStore as "" uses the script's working directory 
FileStore=""  
exe32 = "JRE_32.exe"
exe64 = "JRE_64.exe"

'0 will remove JRE, 1 will update existing JRE,  2 will deploy and/or update JRE, 3 functions as option 1 but will also deploy missing JRE if opposite bitness is installed
x86=1
x64=1
 
'Add any extra Java CLI switches 
'http://docs.oracle.com/javase/8/docs/technotes/guides/install/windows_installer_options.html#A1097528 
'URL Updated for Java 8 Options 
'Example: switches="/s INSTALLDIR=D:\Program Files(x86)\Java\" 
switches32="/s "
switches64="/s "

'Log parameters, you set logging to 1 and/or comment out 'On Error Resume Next'
logging = 0
logdir = ""
On Error Resume Next
'=================================================================== 
Set App = CreateObject("Shell.Application") 
Set objFSO = CreateObject("Scripting.FileSystemObject") 
Set oShell = WScript.CreateObject("WScript.Shell")  
Set installer = CreateObject("WindowsInstaller.Installer")
Set req = CreateObject("MSXML2.ServerXMLHTTP.6.0") 
Set objXMLHTTP = CreateObject("MSXML2.ServerXMLHTTP.6.0") 
Set colNamedArguments = WScript.Arguments.Named
Set objArgs = Wscript.Arguments

'Parse parameters
If colNamedArguments.Item("Download") <> "" Then Download = colNamedArguments.Item("Download")
If colNamedArguments.Item("Modify") <> "" Then Modify = colNamedArguments.Item("Modify")
If colNamedArguments.Item("FileStore") <> "" Then FileStore = colNamedArguments.Item("FileStore")
If colNamedArguments.Item("x86") <> "" Then x86 = colNamedArguments.Item("x86")
If colNamedArguments.Item("x64") <> "" Then x64 = colNamedArguments.Item("x64")
If colNamedArguments.Item("switches32") <> "" Then switches32 = colNamedArguments.Item("switches32")
If colNamedArguments.Item("switches64") <> "" Then switches64 = colNamedArguments.Item("switches64")
If colNamedArguments.Item("logging") <> "" Then logging = colNamedArguments.Item("logging")
If colNamedArguments.Item("logdir") <> "" Then logdir = colNamedArguments.Item("logdir")
If colNamedArguments.Item("exe32") <> "" Then exe32 = colNamedArguments.Item("exe32")
If colNamedArguments.Item("exe64") <> "" Then exe64 = colNamedArguments.Item("exe64")

If oShell.ExpandEnvironmentStrings("%PROCESSOR_ARCHITECTURE%") = "x86" Then x64=1

areAdmin = false
 
'If FileStore was not specified use the script's working directory
If FileStore = "" Then FileStore = objFSO.GetParentFolderName(WScript.ScriptFullName) & "\" 
'Verify FileStore has trailing backslash
If Mid(FileStore, Len(FileStore),1) <> "\" Then FileStore = FileStore & "\"

file32 = FileStore & exe32
file64 = FileStore & exe64

'Do the same for logdir
If logdir = "" AND logging = 1 Then logdir = FileStore
If logging = 1 Then
	If Mid(logdir, Len(logdir),1) <> "\" Then logdir = logdir & "\"
End if
ErrorLog = logdir & oShell.ExpandEnvironmentStrings("%computername%") &  "_error.log" 

'The logging function
Function LogIt(task, result)
TimeStamp = now()
If logging = 1 Then
	'Verify LogDir Exists, if not, create it, failure to create folder will not be logged for obvious reasons
    If Not objFSO.FolderExists(logdir) Then objFSO.CreateFolder(logdir)
	If Err.Number <> 0 Then
		objFSO.OpenTextFile(ErrorLog, 8, True).WriteLine TimeStamp & " " & task & " ERROR " & Err.Description
		Err.Clear
	Else 
		objFSO.OpenTextFile(ErrorLog, 8, True).WriteLine TimeStamp & " " & task & " SUCCESS " & result
	End if
End if
End Function

If Download = 1 Then
	Call LogIt("Download_Check", "Download set to 1, attempting to query Java and download latest bundle")
	'Verify FileStore Exists, if not, create it	
    If Not objFSO.FolderExists(FileStore) Then 
		Call LogIt("Verify_FileStore", FileStore & " directory/share does not exist, attempting to create it...")
		objFSO.CreateFolder(FileStore)
		Call LogIt("Create_FileStore", "Created FileStore: " & FileStore)
	End if
    DownloadLog = FileStore & "Download.log" 

    'Create the log that records the last download bundle ID 
    If Not objFSO.FileExists(DownloadLog) Then
		Call LogIt("Verify_DownloadLog", DownloadLog & " does not exist, attempting to create it...")
        header = "Current Java Bundle Log: "  
        objFSO.OpenTextFile(DownloadLog, 8, True).WriteLine header
		Call LogIt("Create_DownloadLog", "Created DownloadLog: " & DownloadLog)
    End if 

    Set openLog = objFSO.OpenTextFile(DownloadLog, 1, True) 
    readLog = openLog.ReadAll 
	Call LogIt("Read_DownloadLog", "")
	
    'Query java.com
    req.open "GET", "http://www.java.com/en/download/manual.jsp", False 
    req.setRequestHeader "User-Agent", "Mozilla/5.0 (Windows NT 6.1; WOW64)" 
    req.send()
	Call LogIt("Sending_Request", "")
    'Parse query response 
    Call parseCheck(" Offline", file32, bundle32) 
    Call parseCheck(" (64-bit)", file64, bundle64)
Else
	Call LogIt("Download_Check", "Download not set to 1, skipping query/download stage")
End If 

Function parseCheck(str, str2, bndl) 
    strArr = split(req.responseText, "Download Java software for Windows" & str) 
    strArr2 = split(strArr(1), Chr(34))  
    bndl = strArr2(2) 
	Call LogIt("Parse_Response", "BundleURL=" & bndl)
    If instr(readLog, bndl) = false Then
		Call LogIt("Verify_URL", "Bundle URL not found in Download.log, adding to log, attempting download...")
        objFSO.OpenTextFile(DownloadLog, 8, True).WriteLine Date & "|" & bndl 
        'Our bundle is out-of-date, download latest 
        Call getBundle(str2, bndl)
	Else
		If str = " Offline" AND objFSO.FileExists(file32) = false Then
			Call LogIt("Verify_URL", "Bundle URL found in Download.log but existing file32 not found in FileStore... downloading bundle")
			Call getBundle(str2, bndl)
			Else if str = " Offline" Then
				Call LogIt("Verify_URL", "URL found in log, no need to download")
			End if
		End if
		If str = " (64-bit)" AND objFSO.FileExists(file64) = false Then
			Call LogIt("Verify_URL", "Bundle URL found in Download.log but existing file64 not found in FileStore... downloading bundle")
			Call getBundle(str2, bndl)
			Else if str = " (64-bit)" Then
				Call LogIt("Verify_URL", "URL found in log, no need to download")
			End if
		End if
    End If  
End Function 
 
Function getBundle(fName, bURL) 
    objXMLHTTP.open "GET", bURL, false  
    objXMLHTTP.send()  
    If objXMLHTTP.Status = 200 Then  
		Call LogIt("Download_Response", "Request Status=" & objXMLHTTP.Status & " Downloading file stream")
        Set objADOStream = CreateObject("ADODB.Stream")  
        objADOStream.Open  
        objADOStream.Type = 1  
        objADOStream.Write objXMLHTTP.ResponseBody  
        objADOStream.Position = 0    
        If objFSO.FileExists(fName) Then 
			Call LogIt("Detect_OldFile", fName & " exists, deleting...")
			objFSO.DeleteFile fName
			Call LogIt("Purge_OldFile", fName & " deleted")
		End if
        objADOStream.SaveToFile fName  
        objADOStream.Close  
		Call LogIt("Save_NewFile", "Saved stream to " & fName)
	Else
		Call LogIt("Bundle_Request", " WARNING, response status not 200")
	End if
End Function 

	
 
'Compare version numbers 
Function chkArr(arr1, arr2, i) 
    If (CLng(arr1(i)) < (CLng(arr2(i)))) Then  
        chkArr = True 
        Exit Function 
    End If     
    If (UBound(arr1) > i) And (UBound(arr2) > i) Then chkArr = chkArr(arr1, arr2, i + 1) 
End Function 
 
If Modify = 1 Then
	Call LogIt("Modify_Check", "ModifyJRE set to 1, Confirming files and examining installed versions for removal")
    If objFSO.FileExists(file32) Then 
		store32 = objFSO.GetFileVersion(file32)
		Call LogIt("Confirm_x86_File", "x86 file found, version=" & store32)
	Else
		store32 = "0.0.0.0"
		Call LogIt("Confirm_x86_File", "x86 file not found, skipping install, only checking for removal setting compare version to 0.0.0.0")
	End if
    If objFSO.FileExists(file64) Then 
		store64 = objFSO.GetFileVersion(file64)
	Call LogIt("Confirm_x64_File", "x64 file found, version=" & store32)
	Else
		store64 = "0.0.0.0"
		Call LogIt("Confirm_x64_File", "x64 file not found, skipping install, only checking for removal setting compare version to 0.0.0.0")
	End if
	
    'Search for old Java installs 
        For Each product In installer.Products 
        'If product is JRE 
        If InStr(product, "26A24AE4-039D-4CA4-87B4-") Then 
            Version = installer.ProductInfo(product, "VersionString")
            'If installed JRE is 32 bit 
            If InStr(Mid(product,28,3), "32") Then
				If x64 = 3 Then x64 = 2
				If x86 = 3 Then x86 = 2
				Call LogIt("Found_Installed_x86", "Found 32-bit JRE installed version= " & Version)
                'If installed JRE is out-of-date or we specified removal 
                If (chkArr(Split(Version, "."), Split(store32, "."), CInt(0)) = True) Or x86 = 0 Then
					Call LogIt("Remove_JRE", "Installed version is not up-to-date or removal was specified, Checking for administrative rights")
                    If areAdmin = false Then Call IsElevated
					Call LogIt("Confirm_Admin", "Confirmed administrative rights")
                    oShell.run("msiexec.exe /x " & product & " /qn"), 1, true
					Call LogIt("Uninstall_JRE", "Uninstalled MSI product " & product)					
                    If x86 = 1 Then x86 = 2
				'This version of JRE is up-to-date, if x86 is set to deploy (2) we can set it back to modify only (no need to reinstall)
                Else If x86 = 2 Then x86 = 1                      
                End If  
            End If 
            If InStr(Mid(product,28,3), "64") Then
				If x64 = 3 Then x64 = 2
				If x86 = 3 Then x86 = 2
				Call LogIt("Found_Installed_x64", "Found 64-bit JRE installed version= " & Version)
                If (chkArr(Split(Version, "."), Split(store64, "."), CInt(0)) = True) Or x64 = 0 Then
					Call LogIt("Remove_JRE", "Installed version is not up-to-date or removal was specified, Checking for administrative rights")
                    If areAdmin = false Then Call IsElevated
					Call LogIt("Confirm_Admin", "Confirmed administrative rights")
                    oShell.run("msiexec.exe /x " & product & " /qn"), 1, true 
					Call LogIt("Uninstall_JRE", "Uninstalled MSI product " & product)	
                    If x64 = 1  Then x64 = 2
				'This version of JRE is up-to-date, if x64 is set to deploy (2) we can set it back to modify only (no need to reinstall)
                Else If x64 = 2 Then x64 = 1 
                End If 
            End If 
        End if  
    Next
	Call LogIt("Removal_Complete", "")

    'If FileStore is UNC, transfer files 
    If  (Mid(FileStore,1,2) = "\\") And ((x86 = 2) Or (x64 = 2)) Then
		Call LogIt("UNC_Detected", "Install files are located on a file share, transferring locally")
        temp = oShell.ExpandEnvironmentStrings("%temp%") 
        Set TypeLib = CreateObject("Scriptlet.TypeLib") 
        tmpFolder = objFSO.CreateFolder(temp & "\" & TypeLib.Guid)
		Call LogIt("Create_TEMP_Dir", "TEMP directory created: " & tmpFolder)
        objFSO.CopyFile FileStore & "JRE_*", tmpFolder, True 
        file32 = tmpFolder & "\" & objFSO.GetFileName(file32)
		Call LogIt("Target_32", "New 32-bit filename: " & file32)		
        file64 = tmpFolder & "\" & objFSO.GetFileName(file64)
		Call LogIt("Target_64", "New 64-bit filename: " & file64)	
		Call LogIt("Transfer_Files", "File(s) transferred")
    End If 
    'Install the latest JRE
    If x86 = 2 And objFSO.FileExists(file32) Then
		Call LogIt("Installing_x86", "x86 set for install")	
        If areAdmin = false Then Call IsElevated
		Call LogIt("Confirm_Admin", "Confirmed administrative rights")
        oShell.run(chr(34) & file32 & chr(34) & " " & switches32), 1, true
		Call LogIt("Install_x86_Result", "x86 installed")	
    End If 
    If x64 = 2 And objFSO.FileExists(file64) Then
		Call LogIt("Installing_x64", "x64 set for install")	
        If areAdmin = false Then Call IsElevated
		Call LogIt("Confirm_Admin", "Confirmed administrative rights")
        oShell.run(chr(34) & file64 & chr(34) & " " & switches64), 1, true
		Call LogIt("Install_x64_Result", "x64 installed")	
    End If
	
    If objFSO.FolderExists(tmpFolder) Then 
		objFSO.DeleteFolder tmpFolder, True
		Call LogIt("Delete_tmpFolder", "Temporary folder deleted")	
	End if
    'Uninstall the Java Update Scheduler 
    For Each product In installer.Products 
        If InStr(product, "4A03706F-666A-4037-7777-5F2748764D10") Then
			Call LogIt("Remove_Scheduler", "Java Update Scheduler detected, attempting uninstall")	
            If areAdmin = false Then Call IsElevated
			Call LogIt("Confirm_Admin", "Confirmed administrative rights")
            oShell.run("msiexec.exe /X{4A03706F-666A-4037-7777-5F2748764D10} /qn"), 1, true
			Call LogIt("Removal_Result", "Scheduler uninstalled")	
        End if 
    Next 
End If 
 
Function IsElevated 
    IsElevated = CreateObject("WScript.Shell").Run("cmd.exe /c ""whoami /groups|findstr S-1-16-12288 """, 0, true) = 0 
    If IsElevated = false Then
	'We need to restart the script with runas, reconstruct the arguments list
	'This is a huge pain since using an arg loop doesn't retain the quotes and passing args without them will fail of course
	startArgs = "/Download:" & Download & " /Modify:" & Modify & " /FileStore:" & Chr(34) & FileStore & Chr(34) & " /x86:" & x86 & " /x64:" & x64 & _
	" /switches32:" & Chr(34) & switches32 & Chr(34) &  " /switches64:" & Chr(34) & switches64 & Chr(34) & " /logging:" & logging & _
	" /logdir:" & Chr(34) & logdir & Chr(34) & " /exe32:" & Chr(34) & exe32 & Chr(34) & " /exe64:" & Chr(34) & exe64 & Chr(34)
		
	Call LogIt("Not_Admin", "Script is not running with elevated privileges, restarting")
	Call LogIt("Build_Arguments", "Recreated Arguments string= " & startArgs)	
        App.ShellExecute "wscript.exe", Chr(34) & WScript.ScriptFullName & Chr(34) & " " & startArgs, "", "runas"
	Call LogIt("Restart_Script", "Restarting script with runas")
        wscript.quit  
    Else
		Call LogIt("Admin_Detected", "Running with elevated privileges, setting areAdmin to true")
        areAdmin = true 
    End If 
End function 