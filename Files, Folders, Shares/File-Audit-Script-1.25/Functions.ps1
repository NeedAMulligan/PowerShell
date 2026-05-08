# This function decides if the object is a file or a folder
# http://blogs.technet.com/b/heyscriptingguy/archive/2014/08/31/powertip-using-powershell-to-determine-if-path-is-to-file-or-folder.aspx
Function Is_a_File
{
    # If the path still exists, we can know for certain if it's a file or folder
    Try {If ((Get-Item $Object) -is [System.IO.FileInfo]) {Return $True}}
    
    # If the path is gone, we'll assume that it's a file if it contains a period.
    Catch {If ($Object -like "*.*") {Return $True}}
}

# ************************************************************************************************

# This function returns just the filename from a full path.
Function Get_FileName ($fullpath)

    {If ($fullpath -ne $null) {Return $fullpath.Split('\')[-1]}}

# ************************************************************************************************

# This function returns just the foldername from a full path.
Function Get_FolderName ($fullpath)

    {If ($fullpath -ne $null) {Return $fullpath.Substring(0,$fullpath.LastIndexOf("\"))}}

# ************************************************************************************************

# This function checks to see if the file should be ignored. 
Function Is_Temporary
{    
    $TheFile = (Get_FileName $Object)
    
    # Check that the full path is long enough to be applicable, then ask if the file's last few characters match a temporary extension.
    $Temp_Files | ForEach {If ($Object.length -ge $_.length -AND $Object.substring($Object.length - $_.length, $_.length) -eq $_) {Return $True}}

    If ($TheFile.substring(0,1) -eq "~") {Return $True}
    If ($TheFile -eq "thumbs.db") {Return $True}
    If ($TheFile.length -ge 4 -AND $TheFile.substring(0,4) -eq ".dat") {Return $True}
    
    Return $False
}

# ************************************************************************************************

# This function empties out the Pending_Delete array, deciding whether the file was created/modified or deleted.
Function CleanUp ($Seconds2Wait)
{ 
    ForEach ($Key in $Pending_Delete.Keys)
    {               
        # Calculate the number of seconds
        $TimeSpan = -((New-TimeSpan -Start $Time -End $Pending_Delete[$Key].TimeCreated).TotalSeconds)
        
        # Wait 5 seconds before pronouncing a file "created" to avoid false positives (because maybe a final "Delete" is coming up next)
        If ($TimeSpan -ge 5 -AND $Pending_Delete[$Key].Alive)
        {
            Audit_Report_Add $Pending_Delete[$Key].User "created/modified" $Key "" $Pending_Delete[$Key].TimeCreated ""
            # Mark the item for removal from the list of deleted items
            $MyGarbage.Add($Key)
        }
        # Conclude that the object was deleted if it hasn't been referenced in the past $Seconds2Wait
        # I was using the .Confirmed tag for this, but PDF printers were triggering false positives.
        ElseIf ($TimeSpan -ge $Seconds2Wait)
        {
            If ($Pending_Delete[$Key].Confirmed)
                {Audit_Report_Add $Pending_Delete[$Key].User "deleted" $Key "" $Pending_Delete[$Key].TimeCreated "Confirmed = True"}
            Else
                {Audit_Report_Add $Pending_Delete[$Key].User "renamed/moved" $Key "" $Pending_Delete[$Key].TimeCreated "Aged out"}
            # Mark the item for removal from the list of deleted items
            $MyGarbage.Add($Key)
        }
    }
    
    # You can't remove items from a hashtable and then continue enumerating it, so this is a work-around.
    ForEach ($Item in $MyGarbage) {$Pending_Delete.Remove($Item)}
    # Clear this temporary array now that I'm done with it.
    $MyGarbage.Clear()
}

# ************************************************************************************************

# This function checks if it should ignore changes to the C:\Windows directory (e.g. Windows Updates).
Function Exclude_Path ($Source1)
{
 
    If ($Source1.Length -ge 10 -and $Source1.Substring(0,10) -eq "C:\Windows") {Return $TRUE}

    Return $FALSE
}

# This function facilitates a readable report by (optionally) excluding service accounts.
Function Exclude_User ($User1)
{
    $Ignored_Users | ForEach {If ($User1 -eq $_) {Return $TRUE}}
    
    Return $FALSE
}

# ************************************************************************************************

# This function suppresses duplicate lines lines in the report.
# A default value of " " is assigned to each parameter in case no value was specified when the function was called.
Function Audit_Report_Add ($User1 = " ",$Action1 = " ",$Source1 = " ",$Destination1 = " ",$Time1 = " ",$DebugNotes1 = " ")
{
    # Attempt to show the person's full name instead of just their username
    $User1 = Try{[string](Get-ADUser $User1).Name} Catch {$User1}

    # The current line that we'd like to write into the report.
    $NewLine = $User1 + "," + $Action1 + ",`"" + $Source1 + "`""
    # The last line that was written into the report.
    # On Server 2008 R2 w/ .NET 3.5, I wasn't able to reference the last item in a System.Collections.ArrayList via [-1], so used this way instead.
    $LastLine = Try{$Audit_Report[$Audit_Report.Count-1].Substring(0,$NewLine.Length)} Catch {" "}
   
    # If the new line isn't a duplicate and both the user and path are approved, then add it to the report.
    If (($LastLine -ne $NewLine) -AND -NOT (Exclude_User $User1) -AND -NOT (Exclude_Path $Source1))

    {$Audit_Report.Add($User1 + "," + $Action1 + ",`"" + $Source1 + "`",`"" + $Destination1 + "`"," + $Time1 + "," + $DebugNotes1)} 
}

# ************************************************************************************************

# This function increases the number of logs you can save by compressing them to save disk space
Function Compress_Logs
{
    Try 
    {
        # You'll need the command-line version of 7-zip (www.7-zip.org) in the $LogPath directory
        Set-Location $LogPath
        Start-Process -FilePath "7za.exe" -ArgumentList "a $ZipName Archive-Security*" -Wait

        # Manually trigger .NET garbage collection to close open file handles so security logs can be deleted after compression.
        [System.GC]::Collect()
        Sleep 60

        # Delete the originals now that they're zipped.
        Get-ChildItem ($LogPath + "Archive-Security*") | Remove-Item
    }
    Catch
    {
        "$Start_Time Unable to zip/delete the logs.  Maybe you need to put `"7za.exe`" in $LogPath" | Out-File ($LogPath + "A WARNING.txt") -Append
    }
}

# This optional function deletes old logs so they don't accumulate forever
Function Prune_Logs ($Days2Retain)
{
    # Gather all the zip files older than the specified number of days and delete them.
    Get-ChildItem *.zip | ? {$_.LastWriteTime -lt (Get-Date).AddDays(-$Days2Retain)} | Remove-Item
}

# ************************************************************************************************

# This function sends the day's audit report by email
Function Send_Email ([Parameter(ValueFromPipeline=$true)]$Report_in_CSV)
{
    # Count the number of deleted and modified files
    $Total_Modified = ($Report_in_CSV | Import-CSV | Where-Object {$_.Action -like "created*"}).Count
    $Total_Deleted = ($Report_in_CSV | Import-CSV | Where-Object {$_.Action -like "deleted"}).Count

    # Summarize the activity into an email subject
    $Email_Subject = "↓ $Total_Deleted     ↑ $Total_Modified"

    Send-MailMessage -from $Email_From -to $Email_To -subject $Email_Subject -body "`r`n`r`n" -smtpserver $Email_Server -Attachments $Report_in_HTML -Encoding $Email_Encoding
}

# ************************************************************************************************

Function Export_HTML ([Parameter(ValueFromPipeline=$true)]$Report_in_CSV)
{

  # Calculate how long the script took to run
  $Total_Time = [math]::Round((New-TimeSpan -Start $Start_Time -End (Get-Date)).TotalMinutes,2)
  $Rate = [math]::Round($script:Total_Events / $Total_Time,0)

# Create a header for the HTML report
# This is called a "Here-String" and it cannot be indented
$Header = @"

<script src="https://ajax.googleapis.com/ajax/libs/jquery/1.11.3/jquery.min.js"></script>
<script type="text/javascript" src="http://cdn.datatables.net/1.10.7/js/jquery.dataTables.min.js"></script>
<link rel="stylesheet" type="text/css" href="http://cdn.datatables.net/1.10.7/css/jquery.dataTables.min.css">

<script>

    `$(document).ready(function() {
        `$('#myTable').dataTable( {
            "lengthMenu": [[10, 25, 50, -1], [10, 25, 50, "All"]],
            "iDisplayLength": 25,
            "order": []
         } );
     } );

</script> 

<style>
th, td { white-space: nowrap }
TD + TD + TD + TD + TD + TD {color: white}
</style>

<title>
Audit of changed files
</title>
"@

# Create a footer for the HTML report
$HTML_Report_Post_Text = @"
<font size=1>
<p>This report lists files/folders that were created/modified, renamed, moved, or deleted on $('{0:D}' -f $Start_Time)</p>
<p>Tested on servers running 2008 R2, 2012, 2012 R2 with clients running Windows 7 and 8.1.</p>
<p>The Windows Security Event Logs underlying this script are compressed and retained for 90 days by default.</p>
<p>Processed $script:Total_Events events in $Total_Time minutes ($Rate events per minute).</p></font>
"@

    # The "Replace" statements 1) insert tags and remove the "colgroup" thing...both required for the DataTables plugin to work.
    # Powershell 4 puts the "colgroup" thing all on one line...Powershell 2.0 spreads it out over multiple lines.

    $html = $Report_in_CSV | Import-CSV | ConvertTo-HTML -Fragment
    $html = $html -Replace "<table>", "<table id=`"myTable`" class=`"display`" cellspacing=`"0`" width=`"100%`"><thead>" `
    -Replace "</th></tr>", "</th></tr></thead><tbody>" `
    -Replace "</table", "</tbody></table" `
    -Replace "<colgroup><col/><col/><col/><col/><col/><col/></colgroup>", "" `
    -Replace "<colgroup>", "" `
    -Replace "<col/>", "" `
    -Replace "</colgroup>", ""

    # Output the audit results to an HTML file
    ConvertTo-HTML -Head $Header -body $html -PostContent $HTML_Report_Post_Text | Out-File $Report_in_HTML

    # Output to the pipeline
    Write-Output $Report_in_HTML
}

# ************************************************************************************************

# The Powershell pipeline lets a script process large log files while keeping memory usage flat (Powershell Deep Dives, page 221).
Function Draw_Conclusions ([Parameter(ValueFromPipeline=$true)]$Raw_Event)
{
  
# Without the Begin...Process...End structure, Powershell assumes the whole function is a "begin" and only runs it once, instead of "processing" every item in the pipeline.
BEGIN {}

PROCESS 
    {      
     
      # Count how many events are processed
      $script:Total_Events++
      
      # Convert the event into an XML object
      # http://blogs.technet.com/b/ashleymcglone/archive/2013/08/28/powershell-get-winevent-xml-madness-getting-details-from-event-logs.aspx
      Try{$EventXML = [xml]$Raw_Event.ToXML()} Catch {Audit_Report_Add "Unable to convert an event to XML"}
      
      # Loop through the XML values and turn them into a hashtable for easy access.
      # http://learn-powershell.net/2010/09/19/custom-powershell-objects-and-performance/
      # http://stackoverflow.com/questions/10847573/changing-powershell-pipeline-type-to-hashtable-or-any-other-enumerable-type
      $Event = @{}
      ForEach ($object in $EventXML.Event.EventData.Data) {$Event.Add($object.name,$object.'#text')}
      $Event.Add("ID",$Raw_Event.ID)
      $Event.Add("TimeCreated",$Raw_Event.TimeCreated)

      # Improve script readability through shorter names
      $User = $Event.SubjectUserName
      $Object = $Event.ObjectName
      $Time = $Event.TimeCreated
           
      If ($Event.ID -eq "4656" -AND                           # Event 4656 = a handle was requested.
              -NOT (Is_Temporary)  -AND                       # Exclude temporary files.
              $Pending_Delete.ContainsKey($Object))           # It's common for a "Delete" event to be logged right before a file is created/saved.

               # The file was not deleted, so mark it as created/modified.
               {$Pending_Delete[$Object].Alive = $TRUE}

      ElseIf ($Event.ID -eq "4663" -AND                       # Event 4663 = object access.
              $Event.AccessMask -eq "0x10000" -AND            # 0x10000 = Delete, but this can mean different things - delete, overwrite, rename, move.
              -NOT (Is_Temporary) -AND                        # Exclude temporary files
              -NOT ($Object -like "*`$RECYCLE.BIN\`$I*"))     # Ignore metadata files in the recycle bin.
      
              {
              # Is it already in the list?  If so, kick it out and replace it.  The most recent handle is used to track a moved file.
              If ($Pending_Delete.ContainsKey($Object)) {$Pending_Delete.Remove($Object)}
              
              # Record the filename, username, handle ID, and time.
              $Pending_Delete.Add($Object,@{User = $User; HandleID = $Event.HandleId; TimeCreated = $Time; Alive = $FALSE; Confirmed = $FALSE})
              }

      ElseIf ($Event.ID -eq "4663" -AND                       # Event 4663 = object access.
              $Event.AccessMask -eq "0x2" -AND                # 0x2 = is a classic "object was modified" signal.
              -NOT (Is_Temporary) -AND                        # Exclude temporary files.
              -NOT ($Object -like "*`$RECYCLE.BIN*") -AND     # Exclude files added to the recycle bin
              (Is_a_File))                                    # Exclude folders

              {
                  Audit_Report_Add $User "created/modified" $Object "" $Time "0x2 AccessMask"
                  # The file was not actually deleted, so remove it from this array.
                  $Pending_Delete.Remove($Object)
              }
      
      ElseIf ($Event.ID -eq "4663" -AND
              $Event.AccessMask -eq "0x80")                   # A 4663 event with 0x80 (Read Attributes) is logged
          {                                                   # with the same handle ID when files/folders are moved or renamed.
            
            ForEach ($Key in $Pending_Delete.Keys) 
            {
                # If the Handle & User match...and the object wasn't deleted...figure out whether it was moved or renamed.
                If ($Pending_Delete[$Key].HandleID -eq $Event.HandleID -AND
                $Pending_Delete[$Key].User -eq $User -AND
                $Object -ne $Key -AND
                -NOT $Pending_Delete[$Key].Confirmed -AND
                -NOT (Is_Temporary))
                {                                               
                    # Files moved to a different folder (same filename, different folder)
                    If ((Get_FileName $Object) -ceq (Get_FileName $Key))
                    {    
                        Audit_Report_Add $User "moved" $Key $Object $Time
                        $Pending_Delete.Remove($Key)
                    }
                    
                    # Files moved into the recycle bin
                    ElseIf ($Object -like "*`$RECYCLE.BIN*")
                    {
                        Audit_Report_Add $User "recycled" $Key $Object $Time
                        $Pending_Delete.Remove($Key)
                    }
                    
                    # Files moved out of the recycle bin
                    ElseIf ($Key -like "*`$RECYCLE.BIN*")
                    {
                        Audit_Report_Add $User "restored" $Key $Object $Time
                        $Pending_Delete.Remove($Key)
                    }

                    # Created / renamed files
                    ElseIf ((Get_FolderName $Object) -ceq (Get_FolderName $Key))
                    {
                        If ((Get_FileName $Key) -eq "New Folder")
                            {Audit_Report_Add $User "created" $Object "" $Time}
                        Else
                            {Audit_Report_Add $User "renamed" $Key $Object $Time}
                    
                        $Pending_Delete.Remove($Key)
                    }  
                    Break
                }
            }
              # If none of those conditions match, at least note that the file still exists (if applicable).
              If ($Pending_Delete.ContainsKey($Object)) {$Pending_Delete[$Object].Alive = $TRUE}
          }

      ElseIf ($Event.ID -eq "4659" -AND                     # Event 4659 = a handle was requested with intent to delete
            -NOT (Is_Temporary))                            # Exclude temporary files
            {
            # If you use Windows File Explorer on Server 2012 R2 to delete a file: event 4659 is logged on the destination file server.
            # If you use a command prompt on Server 2012 R2 to delete a file: event 4663 is logged on the destination file server.
            Audit_Report_Add $User "deleted" $Object "" $Time "Event 4659"
            }
      
      # This delete confirmation doesn't happen when objects are moved/renamed; it does when files are created/deleted/recycled.
      ElseIf ($Event.ID -eq "4660")
      {
          ForEach ($Key in $Pending_Delete.Keys)
          {
              If ($Event.HandleID -eq $Pending_Delete[$Key].HandleID -AND
                  $User -eq $Pending_Delete[$Key].User)
                  

                  {$Pending_Delete[$Key].Confirmed = $TRUE}
          }
      }
      
    # Only run the cleanup routine if the event timestamp has incremented by at least one second.
    If ($Time -ne $PreviousTimeStamp) {CleanUp 120}
    # Save the current timestamp for comparison with the next event.
    $PreviousTimeStamp = $Time
        
    }

END {}

}