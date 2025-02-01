# Version 1.25 :: This script reads offline event logs, oldest to newest, bottom to top.
# See http://www.trimideas.com/2015/04/auditing-changed-deleted-files.html for instructions.

# Create a log to aid in troubleshooting
Start-Transcript -path C:\Windows\Temp\Monitor-File-Server-Activity-Log.txt

$ScriptPath = Split-Path $MyInvocation.MyCommand.Path

# "dot sourcing": http://stackoverflow.com/questions/1864128/load-variables-from-another-powershell-script
. $ScriptPath\Variables.ps1
. $ScriptPath\Functions.ps1

# Backup and clear the event log
# https://4sysops.com/archives/managing-the-event-log-with-powershell-part-2-backup
$Security_log = get-wmiobject win32_nteventlogfile -filter "logfilename = 'Security'"
$Security_log.BackupEventlog($Truncated_Log_Path)
Clear-Eventlog "Security"

# Collect all the event logs from today and order them oldest to newest.
$Event_Logs = Get-ChildItem ($LogPath + "*.evtx") | ? {$_.LastWriteTime -ge $Today_Midnight} | Sort LastWriteTime

ForEach ($Log in $Event_Logs)
{
    # Define what we want to pull out of the event log
    $MyFilter = @{Path=($Log).FullName;ID=4656,4659,4660,4663}

    # Retrieve events, oldest to newest...and process 'em.
    Try {Get-WinEvent -FilterHashTable $MyFilter -Oldest | Draw_Conclusions} Catch {"No events found"} 
}

# Flush out the list of deleted items (improbable in production at 11:45pm, but was an issue when testing the script).
CleanUp 0

# Export to CSV
$Audit_Report | Out-File $Report_in_CSV

# Export to HTML for viewing
$Report_in_CSV | Export_HTML

# Send via email if desired
$Report_in_CSV | Send_Email

# Zip the event logs to reduce file size
Compress_Logs

# Delete logs older than 90 days
Prune_Logs 90

Stop-Transcript