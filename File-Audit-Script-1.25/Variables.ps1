$LogPath = "C:\Event_Logs\"
$ReportPath = "C:\Audit\File-Audit-Reports\"
$Email_From = "File Auditing<auditing@yourdomain.com>"
$Email_To = "you@yourdomain.com"
$Email_Server = "your-SMTP-server-goes-here"
$Email_Encoding = New-Object System.Text.utf8encoding # Work-around for a bug in Powershell 2.0 (not needed in version 3 or later).
$Formatted_Date = (Get-Date -UFormat %A-%B-%d-at-%I-%M-%S%p)
$ZipName = "Security-Events-for-" + (Get-Date -UFormat %A-%B-%d) + ".zip"
$Report_in_CSV = $ReportPath + "Audit of changed files on " + $Formatted_Date + ".csv"
$Report_in_HTML = $ReportPath + "Audit of changed files on " + $Formatted_Date + ".html"
$Truncated_Log_Path = $LogPath + "Archive-Security_on_" + $Formatted_Date + ".evtx"
$Today_Midnight = (Get-Date -Hour 0 -Minute 0 -Second 0)
$Total_Events = 0
$Start_Time = Get-Date
# A list of file extensions to ignore
$Temp_Files = "tmp","rgt","mta","tlg",".nd",".ps","log","ldb",":Zone.Identifier","crdownload",".DS_Store",":AFP_AfpInfo",":AFP_Resource"
# A list of users to ignore
$Ignored_Users = "QBDataServiceUser25","Example1"

# Hashtable
# http://blogs.msdn.com/b/mediaandmicrocode/archive/2008/11/27/microcode-powershell-scripting-tricks-the-joy-of-using-hashtables-with-windows-powershell.aspx
$Pending_Delete=@{}

# Dynamically expanding array
# www.jonathanmedd.net/2014/01/adding-and-removing-items-from-a-powershell-array.html
[System.Collections.ArrayList]$Audit_Report=@("User,Action,Source,Destination,Time,DebugNotes")

# Files to purge from the Pending_Delete hashtable
[System.Collections.ArrayList]$MyGarbage=@()

# This allows the Try...Catch error handling to work.
# http://blogs.technet.com/b/heyscriptingguy/archive/2014/07/05/weekend-scripter-using-try-catch-finally-blocks-for-powershell-error-handling.aspx
$ErrorActionPreference = ‘Stop’