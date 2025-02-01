<#PSScriptInfo

.VERSION 1.4

.GUID 545c4386-0fc7-491c-a07d-7da435fdf0ba

.AUTHOR Chris Carter

.COMPANYNAME 

.COPYRIGHT 2016 Chris Carter

.TAGS Messaging Msg.exe WinForms GUI

.LICENSEURI http://creativecommons.org/licenses/by-sa/4.0/

.PROJECTURI https://gallery.technet.microsoft.com/Message-Center-GUI-using-0c587bea

.ICONURI 

.EXTERNALMODULEDEPENDENCIES 

.REQUIREDSCRIPTS 

.EXTERNALSCRIPTDEPENDENCIES 

.RELEASENOTES 


#>

<#
.DESCRIPTION
This script uses Windows Forms to present a GUI for sending messages to remote computers on a network using msg.exe.  You can send to a single computer, multiple computers entered manually, multiple computers from a text file, or you may scan Active Directory for active computers on the network. You can also run this script to change the registry key value AllowRemoteRPC on local computers you would like to send messages.  In a domain environment, you can run this script from a workstation or server with the GPMC installed and create a Group Policy object to affect this change for you.
#>

#Global variable to store whether to run a new admin level process after form is closed
$runAdmin = "No"

#region Import the Assemblies
[reflection.assembly]::loadwithpartialname("System.Drawing") | Out-Null
[reflection.assembly]::loadwithpartialname("System.Windows.Forms") | Out-Null
#endregion

#region Generated Form Objects
$form1 = New-Object System.Windows.Forms.Form

#Custom Additions
#Add objects for MenuStrip
$menu = New-Object System.Windows.Forms.MenuStrip
$menuFile = New-Object System.Windows.Forms.ToolStripMenuItem
$menuHelp = New-Object System.Windows.Forms.ToolStripMenuItem
$menuFileOpen = New-Object System.Windows.Forms.ToolStripMenuItem
$menuFileShortcut = New-Object System.Windows.Forms.ToolStripMenuItem
$menuFileQuit = New-Object System.Windows.Forms.ToolStripMenuItem
$menuHelpDirect = New-Object System.Windows.Forms.ToolStripMenuItem
$menuHelpView = New-Object System.Windows.Forms.ToolStripMenuItem
$menuHelpAbout = New-Object System.Windows.Forms.ToolStripMenuItem
$separatorF = New-Object System.Windows.Forms.ToolStripSeparator
$separatorH = New-Object System.Windows.Forms.ToolStripSeparator
#End Custom Additions

$tabControl1 = New-Object System.Windows.Forms.TabControl
$MsgTab = New-Object System.Windows.Forms.TabPage
$checkBoxAD = New-Object System.Windows.Forms.CheckBox
$buttonClose = New-Object System.Windows.Forms.Button
$buttonSend = New-Object System.Windows.Forms.Button
$grpDomain = New-Object System.Windows.Forms.GroupBox
$checkedListBoxDomain = New-Object System.Windows.Forms.CheckedListBox
$labelDomainComp = New-Object System.Windows.Forms.Label
$grpListComp = New-Object System.Windows.Forms.GroupBox
$buttonClearComp = New-Object System.Windows.Forms.Button
$buttonListComp = New-Object System.Windows.Forms.Button
$textBoxListComp = New-Object System.Windows.Forms.TextBox
$labelListComp = New-Object System.Windows.Forms.Label
$labelMsg = New-Object System.Windows.Forms.Label
$richTextBoxMsg = New-Object System.Windows.Forms.RichTextBox
$OptTab = New-Object System.Windows.Forms.TabPage
$grpLocalComp = New-Object System.Windows.Forms.GroupBox
$buttonEnableReg = New-Object System.Windows.Forms.Button
$labelLocalCompReq = New-Object System.Windows.Forms.Label
$labelLocalComp = New-Object System.Windows.Forms.Label
$labelRegNote = New-Object System.Windows.Forms.Label
$grpPolicy = New-Object System.Windows.Forms.GroupBox
$buttonCreateGPO = New-Object System.Windows.Forms.Button
$labelPolicyReq = New-Object System.Windows.Forms.Label
$labelPolicy = New-Object System.Windows.Forms.Label
$openFileDialog1 = New-Object System.Windows.Forms.OpenFileDialog
$InitialFormWindowState = New-Object System.Windows.Forms.FormWindowState
#endregion Generated Form Objects

#----------------------------------------------
#Generated Event Script Blocks
#----------------------------------------------
#Provide Custom Code for events specified in PrimalForms.

Function Create-MessageBox {
    Param (
        [Parameter(Mandatory=$true)][string]$Message,
        [Parameter(Mandatory=$true)][string]$Title,
        [Parameter(Mandatory=$false)][System.Windows.Forms.MessageBoxButtons]$Buttons="OK",
        [Parameter(Mandatory=$false)][System.Windows.Forms.MessageBoxIcon]$Icon="Information"
    )

    #Pop up Message Box
    [System.Windows.Forms.MessageBox]::Show($Message, $Title, $Buttons, $Icon)
}

Function Test-ADExists {

    #Test for AD Domain Membership *NOTE: Would like to find a more direct way to test this
    #Returns true for existence, false for nonexistence 
    if ($env:USERDOMAIN -ne $env:COMPUTERNAME) {
        $True
    }
    else {
        $False
    }
}

Function Test-Module ([string]$Name) {
    #Test for installation of and import a module
    if (!(Get-Module -Name $Name)) {
        if (Get-Module -ListAvailable | Where-Object {$_.Name -eq $Name}) {
            Import-Module $Name
            $True
        }
        else {$False}
    }
    else {$True}
}

Function Load-CheckedListBox ([System.Windows.Forms.CheckedListBox]$CheckedListBox, $Collection, [switch]$Append) {
    if (!($Append)) {
        $CheckedListBox.Items.Clear()
    }

    if ($Collection -is [Array]) {
        $CheckedListBox.Items.AddRange($Collection)
    }
    else {
        $CheckedListBox.Items.Add($Collection)
    }
}

Function Select-AllBoxes ([System.Windows.Forms.CheckedListBox]$CheckedListBox) {

    #Check if the first box "Select All" was selected
    if ($CheckedListBox.SelectedIndex -eq 0) {
        
        #Iterate through all other boxes
        for ($i = 1; $i -lt $CheckedListBox.Items.Count ; $i++) {
            
            #Switch on the state of "Select All"
            switch ($CheckedListBox.GetItemChecked(0)) {
                #If "Select All" unchecked, uncheck all boxes
                $False {$CheckedListBox.SetItemChecked($i, $False)}
                #If "Select All" checked, check all boxes
                $True {$CheckedListBox.SetItemChecked($i, $True)}
            }
        }
    }
    #Handle the action of all other boxes
    else {
        
        #Test if another box was unchecked
        if (!($CheckedListBox.GetItemChecked($CheckedListBox.SelectedIndex))) {
            #If another box was unchecked, uncheck "Select All"
            $CheckedListBox.SetItemChecked(0, $False)
        }
    }        
}

Function Parse-TextFile ([string]$Path, [System.Windows.Forms.TextBox]$TextBox) {
    
    #Pull down text file and combine into string and insert into Text box
    $compNames = (Get-Content $Path) -join ', '
    $TextBox.Text = $compNames
}

Function Parse-CheckedListBox ([System.Windows.Forms.CheckedListBox+CheckedItemCollection]$ItemCollection) {
    #Combine item collection into string

    #Test for checked items and if exists, combine into string
    #if ($ItemCollection.Count -ne 0) {
        
        #Join the array and remove Select All from the list
        ($ItemCollection -join ',') -replace 'Select All', ''
    #}
}

Function Parse-Input ([string]$Message, [string]$Computers) {
    
    #Split inputs into array of single entries delimiting on whitespace, commas, and semicolons
    [array]$arrComp = (($Computers -replace '[,;\s]', ' ').Trim()) -split '\s+'

    #Pass message and array of computers
    Send-Message -Message $Message -Computers $arrComp
}

Function Send-Message ([string]$Message, [array]$Computers) {

    #Initialize error counter and failed computer names
    $errCount = 0
    $failCompNames = @()

    #Test for message text
    if ($Message) {
        #Test for at least one computer entered
        if ($Computers[0]) {
            #Iterate through array of computer names
            foreach ($computer in $Computers) {
                
                #Call msg.exe to send message to each computer in the array
                Invoke-Expression "msg.exe * /server:$computer `"$Message`""
                #Test exit code from msg.exe and add an error count and the computer name
                if ($LASTEXITCODE -ne 0) {$errCount += 1; $failCompNames += $computer}
            }

            #Test if errors occured
            if ($errCount -ne 0) {
                
                #Format the error message for conjugation and grammatical number
                if ($errCount -eq 1) {$errMsgBegin = "$errCount message was"; $compGramNum = "computer"}
                else {$errMsgBegin = "$errCount messages were"; $compGramNum = "computers"}
                #Generate error message
                $errMessage = "$errMsgBegin unable to be sent to $compGramNum`: $($failCompNames -join ', ').  It is possible that the recipients are not properly configured, or you do not have sufficient privileges to perform this operation. `n
See Help (F1) for details on privileges and configurations."

                #Pop up Send Error Dialog
                Create-MessageBox -Message $errMessage -Title "Messsage Send Error" -Icon Error 
            }
            else {
                #Pop up Send Success Dialog
                Create-MessageBox -Message "Message(s) sent successfully" -Title "Success"
            }
        }
        else {
            #Pop up for no computers entered
            Create-MessageBox -Message "You must enter at least one computer." -Title "No Computers Chosen" -Icon Error
        }
    }
    else {
        #Pop up for no message entered
        Create-MessageBox -Message "There is no message to send" -Title "No Message" -Icon Error
    }
}

Function Enable-ADLookup (
    [System.Windows.Forms.CheckBox]$CheckBox,
    [System.Windows.Forms.CheckedListBox]$CheckedListBox,
    [System.Windows.Forms.GroupBox]$GroupBox) {

    #Check State of CheckBox
    if ($CheckBox.Checked) {
        
        #Test for Active Directory Module and Load if Available, if not Alert
        if (!(Test-Module -Name "ActiveDirectory")) {
            $featuresRequest = Create-MessageBox -Message "The PowerShell Active Directory module did not load.  Either you do not have Remote Server Administration Toos (RSAT) installed, or the module is not enabled in Windows Features. `n
Would you like to go to Windows Features and double check the setting for RSAT?" -Title "Active Directory Warning" -Buttons YesNo -Icon Warning
    
            #If yes, open Windows Features Pane
            if ($featuresRequest -eq "Yes") {Invoke-Expression optionalfeatures; exit}
            #If no, uncheck the AD checkbox
            else {$CheckBox.Checked = $False}
        }

        #If AD Module Loads, Build List of Available Domain Computers and populate checked list box
        else {
                
            #Enable the group box
            $GroupBox.Enabled = $True

            #Scan AD computers and get Names in an array
            Get-ADComputer -Filter * -Properties Name | Sort-Object -Property Name | `
            ForEach-Object -Begin {$domainCompList = @()} -Process {$domainCompList += $_.Name}

            #Add a "Select All" option to checked list box
            $onlineCompList = @("Select All")

            #iterate through Domain Computers to test connection and find online members
            foreach ($entry in $domainCompList) {
                #if test passes, add to online list
                if (Test-Connection -ComputerName $entry -Count 1 -Quiet) {$Lentry = $entry.ToLower(); $onlineCompList += $Lentry}
            }

            #Load checked list box with the list of online computers
            Load-CheckedListBox -CheckedListBox $CheckedListBox -Collection $onlineCompList
        }
    }

    else {
        #When unchecked disable group box and clear check list box
        $GroupBox.Enabled = $False
        $CheckedListBox.Items.Clear()
    }
}

Function Create-RPCGPO ([System.Windows.Forms.Button]$Button) {

    #Test for Group Policy Module and load if available, if not, Alert
    if (!(Test-Module -Name "GroupPolicy")) {
        $featuresRequest = Create-MessageBox -Message "The PowerShell Group Policy module did not load.  Either you do not have Remote Server Administration Toos (RSAT) installed, or the module is not enabled in Windows Features. `n
Would you like to go to Windows Features and double check the setting for RSAT?" -Title "Active Directory Warning" -Buttons YesNo -Icon Warning
    
        #If yes, open Windows Features Pane
        if ($featuresRequest -eq "Yes") {Invoke-Expression optionalfeatures; exit}
        #If no, disable Button
        else {$Button.Enabled = $False}
    }

    #If Group Policy loads, create GPO
    else {
        
        #Get Domain DN to set link target
        [string]$target = ([adsi]'').distinguishedName

        try {
            #Create Group Policy object, Set the appropriate registry key, and link to the top level of domain
            New-GPO "Allow Remote RPC Messages" -Domain $env:USERDNSDOMAIN | Set-GPPrefRegistryValue -Key `
            "HKLM\System\CurrentControlSet\Control\Terminal Server" -ValueName "AllowRemoteRPC" `
            -Type DWord -Value 0x1 -Context Computer -Action Replace | New-GPLink -Target $target
            
            #Catch non-terminating error: i.e., Permission Denied
            if ($?) {
                #Confirmation popup
                Create-MessageBox -Message "Group Policy object created successfully." -Title "GPO Created"
            }
            else {
                #Show error in popup
                Create-MessageBox -Message "An error occurred trying to create the Group Policy object: $($Error[0])" -Title "Error Creating GPO" -Icon Error
            }
        }
        catch {
            #Show error in popup
            Create-MessageBox -Message "An error occurred trying to create the Group Policy object: $_" -Title "Error Creating GPO" -Icon Error
        }
    }
}

Function Enable-RPC {
    
    #Set AllowRemoteRPC Registry Value to 1 if the value is 0 or does not exist
    if (((Get-ItemProperty "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name AllowRemoteRPC -ErrorAction SilentlyContinue).AllowRemoteRPC -eq 0) `
    -or (!(Get-ItemProperty "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name AllowRemoteRPC -ErrorAction SilentlyContinue))) {
        try {
            Set-ItemProperty "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name AllowRemoteRPC -Value 0x1
            
            #Catch Non-terminating error: i.e., Permission Denied
            if ($?) {
                #Confirmation popup
                Create-MessageBox -Message "AllowRemoteRPC value succesfully updated." -Title "Success Updating Registry"
            }
            else {

                #Since non-administrator privileges is a likely scenario with UAC enabled, testing for admin before alerting
                #Test for admin privileges
                if (!([System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
                [System.Security.Principal.WindowsBuiltInRole] "Administrator")) {

                    #Show error in popup with option to run as Admin
                    $script:runAdmin = Create-MessageBox -Message "An error occurred trying to change the registry value: `n$($Error[0]) `
`nIf the error relates to registry access, you should try elevating the program to Administrator level since this script is not currently being run at that level.  Would you like to run this script as an Administrator?" `
                    -Title "Error Altering Registry" -Buttons YesNo -Icon Error
                    if ($runAdmin -eq "Yes") {
                        
                        #Close form so that Start-Process below may start a new Run As process 
                        $script:form1.Close()
                    }
                }
                else {
                    #Show error in popup with no options since admin privileges not the cause
                    Create-MessageBox -Message "An error occurred trying to change the registry value: `n$($Error[0])" `
                    -Title "Error Altering Registry" -Icon Error
                }  
            }
        }

        #Catch terminating error
        catch [System.Exception] {
            #Show error in popup
            Create-MessageBox -Message "An error occurred trying to change the registry value: $_" -Title "Error Altering Registry" -Icon Error
        }
    }

    #Display message if already changed
    elseif ((Get-ItemProperty "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name AllowRemoteRPC -ErrorAction SilentlyContinue).AllowRemoteRPC -eq 1) {
        Create-MessageBox -Message "The AllowRemoteRPC value is already set correctly" -Title "No Change Necessary"
    }
}

Function Create-ViewSourceForm {
    #Add objects for Source Viewer
    $formSourceCode = New-Object System.Windows.Forms.Form
    $richTextBoxSource = New-Object System.Windows.Forms.RichTextBox

    #Form for viewing source code
    $System_Drawing_Size = New-Object System.Drawing.Size
    $System_Drawing_Size.Height = 426
    $System_Drawing_Size.Width = 663
    $formSourceCode.ClientSize = $System_Drawing_Size
    $formSourceCode.DataBindings.DefaultDataSourceUpdateMode = 0
    $formSourceCode.StartPosition = "CenterScreen"
    $formSourceCode.Name = "formSourceCode"
    $formSourceCode.Text = "Message Center Source Script"
    $formSourceCode.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($PSCommandPath)

    $richTextBoxSource.Anchor = 15
    $richTextBoxSource.DataBindings.DefaultDataSourceUpdateMode = 0
    $System_Drawing_Point = New-Object System.Drawing.Point
    $System_Drawing_Point.X = 13
    $System_Drawing_Point.Y = 13
    $richTextBoxSource.Location = $System_Drawing_Point
    $richTextBoxSource.Name = "richTextBoxSource"
    $System_Drawing_Size = New-Object System.Drawing.Size
    $System_Drawing_Size.Height = 401
    $System_Drawing_Size.Width = 638
    $richTextBoxSource.Size = $System_Drawing_Size
    $richTextBoxSource.DetectUrls = $False
    $richTextBoxSource.ReadOnly = $True

    #Get source from script file and add newline to each array item for formatting
    $richTextBoxSource.Text = Get-Content $PSCommandPath | ForEach-Object {$_ + "`n"}

    $formSourceCode.Controls.Add($richTextBoxSource)

    $formSourceCode.Show() | Out-Null
}

Function Create-HelpForm {
    #Add objects for Help
    $formDirections = New-Object System.Windows.Forms.Form
    $richTextBoxHelp = New-Object System.Windows.Forms.RichTextBox
    $InitialFormWindowState = New-Object System.Windows.Forms.FormWindowState
    #endregion Generated Form Objects

    #Help form
    $formDirections.AutoScroll = $True
    $System_Drawing_Size = New-Object System.Drawing.Size
    $System_Drawing_Size.Height = 518
    $System_Drawing_Size.Width = 464
    $formDirections.ClientSize = $System_Drawing_Size
    $formDirections.DataBindings.DefaultDataSourceUpdateMode = 0
    $System_Drawing_Size = New-Object System.Drawing.Size
    $System_Drawing_Size.Height = 556
    $System_Drawing_Size.Width = 480
    $formDirections.MaximumSize = $System_Drawing_Size
    $System_Drawing_Size = New-Object System.Drawing.Size
    $System_Drawing_Size.Height = 556
    $System_Drawing_Size.Width = 480
    $formDirections.MinimumSize = $System_Drawing_Size
    $formDirections.Name = "formDirections"
    $formDirections.StartPosition = 1
    $formDirections.Text = "Help"
    $formDirections.FormBorderStyle = "FixedSingle"
    $formDirections.Icon = [System.IconExtractor]::Extract("imageres.dll", 94, $False)
    $formDirections.MaximizeBox = $False

    $richTextBoxHelp.Anchor = 15
    $richTextBoxHelp.BackColor = [System.Drawing.Color]::FromArgb(255,240,240,240)
    $richTextBoxHelp.BorderStyle = 0
    $richTextBoxHelp.DataBindings.DefaultDataSourceUpdateMode = 0
    $System_Drawing_Point = New-Object System.Drawing.Point
    $System_Drawing_Point.X = 13
    $System_Drawing_Point.Y = 13
    $richTextBoxHelp.Location = $System_Drawing_Point
    $richTextBoxHelp.Name = "richTextBoxHelp"
    $richTextBoxHelp.ReadOnly = $True
    $richTextBoxHelp.SelectionProtected = $True
    $richTextBoxHelp.Cursor = [System.Windows.Forms.Cursors]::Default
    $System_Drawing_Size = New-Object System.Drawing.Size
    $System_Drawing_Size.Height = 493
    $System_Drawing_Size.Width = 439
    $richTextBoxHelp.Size = $System_Drawing_Size
    $richTextBoxHelp.TabIndex = 0
    $richTextBoxHelp.TabStop = $False
    $richTextBoxHelp.Text = 'Message Center Help

Introduction

This script was designed to send popup messages to computers over the network.  This used to be done with net send which was removed from Windows.  In its place, this script uses msg.exe, which was designed to send popup messages to users logged in to a terminal server.  However, with a few registry tweaks or group policy (which this script provides), you will be able to send popup messages to a computer or multiple computers of your choice.

Note about Permissions, Registry, and Group Policy

Non-domain Environment

By default, the AllowRemoteRPC registry key is not enabled in Windows and computers will not be able to receive messages.  In a non-Active Directory environment, you must alter the AllowRemoteRPC registry key value on each individual machine you would like to send messages to.  The key is located at HKLM\System\CurrentControlSet\Control\Terminal Server.  The value must be changed from 0 to 1 hexadecimal value.  Alternately, you can run this script on each computer that you would like to make the change, and select “Enable RPC” from the Registry Options tab.  You must be a member of the local Administrators group of the computer on which these actions are performed.

Domain Environment

By default, the AllowRemoteRPC registry key is not enabled in Windows and computers will not be able to receive messages.  In an Active Directory environment, this can be done with a Group Policy object.  Create a GPO that sets the AllowRemoteRPC registry key value to a hexadecimal value of 1 located in the key HKLM\System\CurrentControlSet\Control\Terminal Server.  To do so, open the Group Policy Management Console and create a new Group Policy object, right-click the new entry and choose Edit.  Then, navigate to Computer Configuration -> Preferences -> Windows Setting -> Right-click Registry and choose New -> Registry Item.  Fill in the information in the dialog box and hit okay.  Link the GPO to the OU, site, or domain is necessary.  For more information about Group Policy, visit http://technet.microsoft.com/en-us/windowsserver/bb310732.aspx  Alternately, you can run this script from a Windows Server 2008 R2 Domain Controller, a Windows Server 2008 member server with the GPMC installed, or Windows 7 with Remote Server Administration Tools (RSAT) installed, and you must be a member of either the Administrators or Group Policy Creator Owners groups  Choose the Registry Options tab and click the “Create GPO” button (the button will not be available if the proper components are not installed).  The created group policy setting is normally applied at boot time, so you may run “gpupdate /force” from a command prompt or PowerShell session on each individual machine if you want to apply the setting immediately.

Sending a message to a single computer

To send a message to a single computer, enter your message in the first text box under the Send Messages tab, then type the hostname of the computer you wish to send a message in the single-line text box below and then click “Send” or press <Enter>.  If your message is successful, you will be notified.

Sending a message to multiple computer

To send a message to multiple computers, enter your message in the first text box under the Send Messages tab, then type the hostnames of the computers you wish to send a message (separated by commas, spaces, or semi-colons).  You may also click “Open” and choose a text (*.txt) file with hostnames of computers already stored (separated by commas, spaces, semi-colons, or carriage returns).  The text file will populate the text box and you may add to the list if you so choose.  Click “Send” or press <Enter> when you are ready to send the messages.  If your messages are successful, you will be notified, or you will be given a list of hostnames that did not receive their messages.

Sending a message to domain computers

To send a message to domain computers, you may follow the steps above for sending to one or multiple computers, or you may also choose to select the “Use Active Directory” checkbox, which will scan Active Directory for computer accounts and test their connections to see if they are available (this feature will not be available if the proper components are not installed).  Once it has gathered its list, it will present a list of checkboxes to select one, multiple, or all domain computers online.  You can combine the techniques from above to send to other computers not in the list as well at the same time.  When you are done choosing your computers and entering your message, click “Send” or press <Enter>.

Viewing source code

You may pull up the source code of the script by choosing Help -> View Script from the menu or by pressing Ctrl + E.

Create Shortcut

If you choose this option in the File menu, a shortcut will be created under All Programs in your personal profile.

Acknowledgements and Contributions

Acknowledgements and contributions are listed under Help ->  About Message Center.  This will include links to resources used.'

    #Handles clicking of links in help document
    $richTextBoxHelp.add_LinkClicked({Invoke-Expression "start $($_.LinkText)"})
        

    $formDirections.Controls.Add($richTextBoxHelp)

    $formDirections.Show() | Out-Null
}

Function Create-AboutForm {
    #Add objects for About
    $formAbout = New-Object System.Windows.Forms.Form
    $richTextBoxAbout = New-Object System.Windows.Forms.RichTextBox
    $InitialFormWindowState = New-Object System.Windows.Forms.FormWindowState

    #About Form
    $formAbout.AutoScroll = $True
    $System_Drawing_Size = New-Object System.Drawing.Size
    $System_Drawing_Size.Height = 445
    $System_Drawing_Size.Width = 464
    $formAbout.ClientSize = $System_Drawing_Size
    $formAbout.DataBindings.DefaultDataSourceUpdateMode = 0
    $formAbout.FormBorderStyle = 1
    $formAbout.Name = "formAbout"
    $formAbout.StartPosition = 1
    $formAbout.Text = "About Message Center"
    $formAbout.Icon = [System.IconExtractor]::Extract("imageres.dll", 76, $False)
    $formAbout.MaximizeBox = $False

    $richTextBoxAbout.Anchor = 15
    $richTextBoxAbout.BackColor = [System.Drawing.Color]::FromArgb(255,240,240,240)
    $richTextBoxAbout.BorderStyle = 0
    $richTextBoxAbout.DataBindings.DefaultDataSourceUpdateMode = 0
    $System_Drawing_Point = New-Object System.Drawing.Point
    $System_Drawing_Point.X = 13
    $System_Drawing_Point.Y = 13
    $richTextBoxAbout.Location = $System_Drawing_Point
    $richTextBoxAbout.Name = "richTextBoxAbout"
    $richTextBoxAbout.ReadOnly = $True
    $richTextBoxAbout.Cursor = [System.Windows.Forms.Cursors]::Default
    $System_Drawing_Size = New-Object System.Drawing.Size
    $System_Drawing_Size.Height = 420
    $System_Drawing_Size.Width = 439
    $richTextBoxAbout.Size = $System_Drawing_Size
    $richTextBoxAbout.TabIndex = 0
    $richTextBoxAbout.TabStop = $False
    $richTextBoxAbout.Text = "About Message Center
Version 1.4

Created by Chris Carter - mailto:powershell@artfullyencoded.com

The author would like to thank:
Pedro Lima - http://pedrofln.blogspot.com/2011/08/net-messenger-script-for-windows-72008.html#en  for giving him the idea for the script and for making his available for download.

Hey, Scripting Guy! Blog - http://blogs.technet.com/b/heyscriptingguy for a truly exhaustive wealth of knowledge that helped put all the separate concepts into a cohesive whole.

Microsoft Technet - http://technet.microsoft.com for providing a guide to everything Windows, PowerShell, and all the rest.

Microsoft Developer Network - http://msdn.microsoft.com for the ability to find the smallest details of any part of the .NET Framework.

Sapien Technologies - http://www.sapien.com/software/powershell_studio for the Primal Forms Community Edition that was used to layout the design of the UI.

And last, but not least:
Jeff Edwards – for providing support, testing, and extensive knowledge of code, concepts, and clarity."

    #Handles clicking the links in about form
    $richTextBoxAbout.add_LinkClicked({Invoke-Expression "start $($_.LinkText)"})

    $formAbout.Controls.Add($richTextBoxAbout)

    $formAbout.Show() | Out-Null
}

#Uses the old WScript.Shell.CreateShortcut() method which is, shockingly, still the best way to do this
#Would love to find a more "PowerShell" alternative
Function Create-Shortcut ($ShortcutPath, $TargetPath, $TargetArgs, $IconLocation, $IconIndex) {
    
    #Test for shortcut existence, if not create
    if (!(Test-Path $ShortcutPath)) {
        $objShell = New-Object -ComObject WScript.Shell
        $shortcut = $objShell.CreateShortcut($ShortcutPath)
        $shortcut.TargetPath = $TargetPath
        $shortcut.Arguments = $TargetArgs
        $shortcut.IconLocation = "$IconLocation, $IconIndex"
        $shortcut.Save()
        
        #Test for success of creation
        if ($?) {
            Create-MessageBox -Message "Shortcut created successfully." -Title "Shortcut Created"
        }
        else {
            Create-MessageBox -Message "There was an error creating the shortcut." -Title "Creation Error" -Icon Error
        }
    }
    else {
        Create-MessageBox -Message "The shortcut already exists." -Title "Shortcut"
    }
}
#End Functions

#Wrapper for VB code calling the ExtractIconEX function from the Windows API
#for extracting icons from .dll, .exe, etc.
#Obtained verbatim from Kazun's post at -
#http://social.technet.microsoft.com/Forums/en/winserverpowershell/thread/16444c7a-ad61-44a7-8c6f-b8d619381a27
$codeIconExtract = @"
using System;
using System.Drawing;
using System.Runtime.InteropServices;

namespace System
{
	public class IconExtractor
	{

	 public static Icon Extract(string file, int number, bool largeIcon)
	 {
	  IntPtr large;
	  IntPtr small;
	  ExtractIconEx(file, number, out large, out small, 1);
	  try
	  {
	   return Icon.FromHandle(largeIcon ? large : small);
	  }
	  catch
	  {
	   return null;
	  }

	 }
	 [DllImport("Shell32.dll", EntryPoint = "ExtractIconExW", CharSet = CharSet.Unicode, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
	 private static extern int ExtractIconEx(string sFile, int iIndex, out IntPtr piLargeVersion, out IntPtr piSmallVersion, int amountIcons);

	}
}
"@

#Add Type to use wrapped Static function for icon extraction
Add-Type -TypeDefinition $codeIconExtract -ReferencedAssemblies System.Drawing

$OnLoadForm_StateCorrection=
{#Correct the initial state of the form to prevent the .Net maximized form issue
	$form1.WindowState = $InitialFormWindowState
}

#----------------------------------------------
#region Generated Form Code
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 585
$System_Drawing_Size.Width = 423
$form1.ClientSize = $System_Drawing_Size
$form1.DataBindings.DefaultDataSourceUpdateMode = 0
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 623
$System_Drawing_Size.Width = 439
$form1.MinimumSize = $System_Drawing_Size

#Custom Additions
$form1.Icon = [System.IconExtractor]::Extract("imageres.dll", 15, $False)
$form1.StartPosition = "CenterScreen"
$form1.Name = "form1"
$form1.Text = "Message Center"
$form1.AcceptButton = $buttonSend
$form1.CancelButton = $buttonClose

#Following Lines add a MenuStrip object which is not available in Primal Forms CE
$menuFileQuit.Text = "&Quit"
$menuFileQuit.ShortcutKeys ="Control, Q" 
$menuFileQuit.add_Click({$form1.Close()})

$menuFileShortcut.Text = "Create &Shortcut"
$menuFileShortcut.ShortcutKeys = "Control, K"

#Handles the Shortcut Menu
$menuFileShortcut.add_Click({
    $menuPath = "$env:userprofile\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\$($form1.Text).lnk"
    $shortTarget = "$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe"
    $shortIcon = "$env:windir\System32\imageres.dll"
    $shortArgs = "-NonInteractive -WindowStyle Hidden -File `"$PSCommandPath`""
    Create-Shortcut -ShortcutPath $menuPath -TargetPath $shortTarget -TargetArgs $shortArgs -IconLocation $shortIcon -IconIndex 15
})

$menuFileOpen.Text = "&Open"
#Left extended version in for future reference to find other keys in enumeration
$menuFileOpen.ShortcutKeys = [System.Windows.Forms.Keys]::Control, [System.Windows.Forms.Keys]::O

#Handles the Open Menu
$menuFileOpen.add_Click({
    $btnChosen = $openFileDialog1.ShowDialog()

    #Sends the chosen text file to be converted to a string
    if ($btnChosen -eq "OK") {
        Parse-TextFile -Path $openFileDialog1.FileName -TextBox $textBoxListComp
    }
})

$menuFile.Text = "&File"
$menuFile.DropDownItems.AddRange(@($menuFileOpen, $separatorF, $menuFileShortcut, $menuFileQuit))

$menuHelpDirect.Text = "Message Center &Help"
$menuHelpDirect.ShortcutKeys = "F1"

#Handles the Directions Menu
#Recreates the form every time to stop error on calling
#a disposed object when using non-modal Form.Show()
$menuHelpDirect.add_Click({Create-HelpForm})

$menuHelpView.Text = "Vi&ew Script"
$menuHelpView.ShortcutKeys = "Control, E"

#Handles the View Script Menu
#Recreates the form every time to stop error on calling
#a disposed object when using non-modal Form.Show()
$menuHelpView.add_Click({Create-ViewSourceForm})

$menuHelpAbout.Text = "&About Message Center"

#Handles the About Menu
#Recreates the form every time to stop error on calling
#a disposed object when using non-modal Form.Show()
$menuHelpAbout.add_Click({Create-AboutForm})

$menuHelp.Text = "&Help"
$menuHelp.DropDownItems.AddRange(@($menuHelpDirect, $menuHelpView, $separatorH, $menuHelpAbout))

$menu.Items.AddRange(@($menuFile, $menuHelp))

$form1.Controls.Add($menu)
#End Custom Additions

$tabControl1.Anchor = 15
$tabControl1.DataBindings.DefaultDataSourceUpdateMode = 0
$System_Drawing_Point = New-Object System.Drawing.Point
$System_Drawing_Point.X = 13
$System_Drawing_Point.Y = 27
$tabControl1.Location = $System_Drawing_Point
$tabControl1.Name = "tabControl1"
$tabControl1.SelectedIndex = 0
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 548
$System_Drawing_Size.Width = 398
$tabControl1.Size = $System_Drawing_Size
$tabControl1.TabIndex = 4

$form1.Controls.Add($tabControl1)
$MsgTab.DataBindings.DefaultDataSourceUpdateMode = 0
$System_Drawing_Point = New-Object System.Drawing.Point
$System_Drawing_Point.X = 4
$System_Drawing_Point.Y = 22
$MsgTab.Location = $System_Drawing_Point
$MsgTab.Name = "MsgTab"
$System_Windows_Forms_Padding = New-Object System.Windows.Forms.Padding
$System_Windows_Forms_Padding.All = 3
$System_Windows_Forms_Padding.Bottom = 3
$System_Windows_Forms_Padding.Left = 3
$System_Windows_Forms_Padding.Right = 3
$System_Windows_Forms_Padding.Top = 3
$MsgTab.Padding = $System_Windows_Forms_Padding
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 522
$System_Drawing_Size.Width = 390
$MsgTab.Size = $System_Drawing_Size
$MsgTab.TabIndex = 0
$MsgTab.Text = "Send Message"
$MsgTab.UseVisualStyleBackColor = $True

$tabControl1.Controls.Add($MsgTab)

$checkBoxAD.DataBindings.DefaultDataSourceUpdateMode = 0

$System_Drawing_Point = New-Object System.Drawing.Point
$System_Drawing_Point.X = 14
$System_Drawing_Point.Y = 300
$checkBoxAD.Location = $System_Drawing_Point
$checkBoxAD.Name = "checkBoxAD"
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 24
$System_Drawing_Size.Width = 365
$checkBoxAD.Size = $System_Drawing_Size
$checkBoxAD.TabIndex = 9
$checkBoxAD.Text = "Use Active Directory (May take time to populate)"
$checkBoxAD.UseVisualStyleBackColor = $True

#Custom Addition
#Enables the check box only if on Active Directory
$checkBoxAD.Enabled = Test-ADExists

#Handles the checkbox that enables AD lookup for computers
$checkBoxAD.add_Click({

    #Sets the form cursor while AD lookup is performed.  Attempted to use Form.UseWaitCursor
    #but it would only take effect after the function for unknown reasons.
    $form1.Cursor = [System.Windows.Forms.Cursors]::WaitCursor

    Enable-ADLookup -CheckBox $checkBoxAD -CheckedListBox $checkedListBoxDomain `
                    -GroupBox $grpDomain
    #Resets the cursor
    $form1.Cursor = [System.Windows.Forms.Cursors]::Default
})
#End Custom Addition

$MsgTab.Controls.Add($checkBoxAD)

$buttonClose.Anchor = 2

$buttonClose.DataBindings.DefaultDataSourceUpdateMode = 0

$System_Drawing_Point = New-Object System.Drawing.Point
$System_Drawing_Point.X = 198
$System_Drawing_Point.Y = 488
$buttonClose.Location = $System_Drawing_Point
$buttonClose.Name = "buttonClose"
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 23
$System_Drawing_Size.Width = 75
$buttonClose.Size = $System_Drawing_Size
$buttonClose.TabIndex = 8
$buttonClose.Text = "Close"
$buttonClose.UseVisualStyleBackColor = $True
$buttonClose.add_Click({$form1.Close()})

$MsgTab.Controls.Add($buttonClose)

$buttonSend.Anchor = 2

$buttonSend.DataBindings.DefaultDataSourceUpdateMode = 0

$System_Drawing_Point = New-Object System.Drawing.Point
$System_Drawing_Point.X = 117
$System_Drawing_Point.Y = 488
$buttonSend.Location = $System_Drawing_Point
$buttonSend.Name = "buttonSend"
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 23
$System_Drawing_Size.Width = 75
$buttonSend.Size = $System_Drawing_Size
$buttonSend.TabIndex = 7
$buttonSend.Text = "Send"
$buttonSend.UseVisualStyleBackColor = $True

#Custom Additions

#Handles the "Send" button
$buttonSend.add_Click({
    
    #Sends the checked list box checked items to the function to be converted to a string
    $domainHostNames = Parse-CheckedListBox -ItemCollection ($checkedListBoxDomain.CheckedItems)

    #Sends the combined contents of the text box and the converted checked list box
    #to be stripped and turned into an array and then sent
    Parse-Input -Message $richTextBoxMsg.Text -Computers ($textBoxListComp.Text + ' ' + $domainHostNames)})

#End Custom Additions

$MsgTab.Controls.Add($buttonSend)

$grpDomain.Anchor = 15

$grpDomain.DataBindings.DefaultDataSourceUpdateMode = 0
$System_Drawing_Point = New-Object System.Drawing.Point
$System_Drawing_Point.X = 7
$System_Drawing_Point.Y = 326
$grpDomain.Location = $System_Drawing_Point
$grpDomain.Name = "grpDomain"
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 156
$System_Drawing_Size.Width = 378
$grpDomain.Size = $System_Drawing_Size
$grpDomain.TabIndex = 6
$grpDomain.TabStop = $False
$grpDomain.Text = "Send to Domain Computers"

#Custom Addition
#Set initial state to disable until AD turned on
$grpDomain.Enabled = $False
#End Custom Addition

$MsgTab.Controls.Add($grpDomain)

$checkedListBoxDomain.Anchor = 15
$checkedListBoxDomain.DataBindings.DefaultDataSourceUpdateMode = 0
$checkedListBoxDomain.FormattingEnabled = $True
$System_Drawing_Point = New-Object System.Drawing.Point
$System_Drawing_Point.X = 7
$System_Drawing_Point.Y = 53
$checkedListBoxDomain.Location = $System_Drawing_Point
$checkedListBoxDomain.Name = "checkedListBoxDomain"
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 94
$System_Drawing_Size.Width = 365
$checkedListBoxDomain.Size = $System_Drawing_Size
$checkedListBoxDomain.TabIndex = 1

#Custom Addition

#Eliminates the need to click the items twice to check
$checkedListBoxDomain.CheckOnClick = $True

#Sends information to the logic that handles the "Select All" option
$checkedListBoxDomain.add_SelectedIndexChanged({Select-AllBoxes $checkedListBoxDomain})

#End Custom Addition

$grpDomain.Controls.Add($checkedListBoxDomain)

$labelDomainComp.Anchor = 13
$labelDomainComp.DataBindings.DefaultDataSourceUpdateMode = 0

$System_Drawing_Point = New-Object System.Drawing.Point
$System_Drawing_Point.X = 6
$System_Drawing_Point.Y = 27
$labelDomainComp.Location = $System_Drawing_Point
$labelDomainComp.Name = "labelDomainComp"
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 23
$System_Drawing_Size.Width = 366
$labelDomainComp.Size = $System_Drawing_Size
$labelDomainComp.TabIndex = 0
$labelDomainComp.Text = "Select the domain computers (must be in an Active Directory domain)"

$grpDomain.Controls.Add($labelDomainComp)


$grpListComp.Anchor = 13

$grpListComp.DataBindings.DefaultDataSourceUpdateMode = 0
$System_Drawing_Point = New-Object System.Drawing.Point
$System_Drawing_Point.X = 7
$System_Drawing_Point.Y = 165
$grpListComp.Location = $System_Drawing_Point
$grpListComp.Name = "grpListComp"
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 129
$System_Drawing_Size.Width = 378
$grpListComp.Size = $System_Drawing_Size
$grpListComp.TabIndex = 5
$grpListComp.TabStop = $False
$grpListComp.Text = "Send to Computers"

$MsgTab.Controls.Add($grpListComp)

$buttonClearComp.DataBindings.DefaultDataSourceUpdateMode = 0

$System_Drawing_Point = New-Object System.Drawing.Point
$System_Drawing_Point.X = 89
$System_Drawing_Point.Y = 98
$buttonClearComp.Location = $System_Drawing_Point
$buttonClearComp.Name = "buttonClearComp"
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 23
$System_Drawing_Size.Width = 75
$buttonClearComp.Size = $System_Drawing_Size
$buttonClearComp.TabIndex = 3
$buttonClearComp.Text = "Clear"
$buttonClearComp.UseVisualStyleBackColor = $True

#Custom Additions
#Clear Computers from the list
$buttonClearComp.add_Click({$textBoxListComp.Clear()})
#End Custom Additions

$grpListComp.Controls.Add($buttonClearComp)

$buttonListComp.DataBindings.DefaultDataSourceUpdateMode = 0

$System_Drawing_Point = New-Object System.Drawing.Point
$System_Drawing_Point.X = 7
$System_Drawing_Point.Y = 98
$buttonListComp.Location = $System_Drawing_Point
$buttonListComp.Name = "buttonListComp"
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 23
$System_Drawing_Size.Width = 75
$buttonListComp.Size = $System_Drawing_Size
$buttonListComp.TabIndex = 2
$buttonListComp.Text = "Open"
$buttonListComp.UseVisualStyleBackColor = $True

#Custom Addition

#Handles the "Open" Button
$buttonListComp.add_Click({
    $btnChosen = $openFileDialog1.ShowDialog()

    #Sends the chosen text file to be converted to a string
    if ($btnChosen -eq "OK") {
        Parse-TextFile -Path $openFileDialog1.FileName -TextBox $textBoxListComp
    }
})
#End Custom Addition

$grpListComp.Controls.Add($buttonListComp)

$textBoxListComp.Anchor = 13
$textBoxListComp.DataBindings.DefaultDataSourceUpdateMode = 0
$System_Drawing_Point = New-Object System.Drawing.Point
$System_Drawing_Point.X = 6
$System_Drawing_Point.Y = 71
$textBoxListComp.Location = $System_Drawing_Point
$textBoxListComp.Name = "textBoxListComp"
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 20
$System_Drawing_Size.Width = 366
$textBoxListComp.Size = $System_Drawing_Size
$textBoxListComp.TabIndex = 1

$grpListComp.Controls.Add($textBoxListComp)

$labelListComp.Anchor = 13
$labelListComp.DataBindings.DefaultDataSourceUpdateMode = 0

$System_Drawing_Point = New-Object System.Drawing.Point
$System_Drawing_Point.X = 6
$System_Drawing_Point.Y = 30
$labelListComp.Location = $System_Drawing_Point
$labelListComp.Name = "labelListComp"
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 37
$System_Drawing_Size.Width = 366
$labelListComp.Size = $System_Drawing_Size
$labelListComp.TabIndex = 0
$labelListComp.Text = "Type the computer name(s) separated by commas or import a list of  names from a text file "

$grpListComp.Controls.Add($labelListComp)


$labelMsg.Anchor = 13
$labelMsg.DataBindings.DefaultDataSourceUpdateMode = 0

$System_Drawing_Point = New-Object System.Drawing.Point
$System_Drawing_Point.X = 7
$System_Drawing_Point.Y = 14
$labelMsg.Location = $System_Drawing_Point
$labelMsg.Name = "labelMsg"
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 23
$System_Drawing_Size.Width = 378
$labelMsg.Size = $System_Drawing_Size
$labelMsg.TabIndex = 0
$labelMsg.Text = "Type your message"

$MsgTab.Controls.Add($labelMsg)

$richTextBoxMsg.Anchor = 13
$richTextBoxMsg.DataBindings.DefaultDataSourceUpdateMode = 0
$System_Drawing_Point = New-Object System.Drawing.Point
$System_Drawing_Point.X = 7
$System_Drawing_Point.Y = 40
$richTextBoxMsg.Location = $System_Drawing_Point
$richTextBoxMsg.Name = "richTextBoxMsg"
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 110
$System_Drawing_Size.Width = 378
$richTextBoxMsg.Size = $System_Drawing_Size
$richTextBoxMsg.TabIndex = 1
$richTextBoxMsg.Text = ""

$MsgTab.Controls.Add($richTextBoxMsg)


$OptTab.DataBindings.DefaultDataSourceUpdateMode = 0
$System_Drawing_Point = New-Object System.Drawing.Point
$System_Drawing_Point.X = 4
$System_Drawing_Point.Y = 22
$OptTab.Location = $System_Drawing_Point
$OptTab.Name = "OptTab"
$System_Windows_Forms_Padding = New-Object System.Windows.Forms.Padding
$System_Windows_Forms_Padding.All = 3
$System_Windows_Forms_Padding.Bottom = 3
$System_Windows_Forms_Padding.Left = 3
$System_Windows_Forms_Padding.Right = 3
$System_Windows_Forms_Padding.Top = 3
$OptTab.Padding = $System_Windows_Forms_Padding
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 522
$System_Drawing_Size.Width = 390
$OptTab.Size = $System_Drawing_Size
$OptTab.TabIndex = 1
$OptTab.Text = "Registry Options"
$OptTab.UseVisualStyleBackColor = $True

$tabControl1.Controls.Add($OptTab)
$grpLocalComp.Anchor = 13

$grpLocalComp.DataBindings.DefaultDataSourceUpdateMode = 0
$System_Drawing_Point = New-Object System.Drawing.Point
$System_Drawing_Point.X = 7
$System_Drawing_Point.Y = 323
$grpLocalComp.Location = $System_Drawing_Point
$grpLocalComp.Name = "grpLocalComp"
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 145
$System_Drawing_Size.Width = 377
$grpLocalComp.Size = $System_Drawing_Size
$grpLocalComp.TabIndex = 2
$grpLocalComp.TabStop = $False
$grpLocalComp.Text = "Local Computer"

$OptTab.Controls.Add($grpLocalComp)

$buttonEnableReg.DataBindings.DefaultDataSourceUpdateMode = 0

$System_Drawing_Point = New-Object System.Drawing.Point
$System_Drawing_Point.X = 7
$System_Drawing_Point.Y = 113
$buttonEnableReg.Location = $System_Drawing_Point
$buttonEnableReg.Name = "buttonEnableReg"
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 23
$System_Drawing_Size.Width = 75
$buttonEnableReg.Size = $System_Drawing_Size
$buttonEnableReg.TabIndex = 2
$buttonEnableReg.Text = "Enable RPC"
$buttonEnableReg.UseVisualStyleBackColor = $True

#Custom Additions
#Handles the "Enable RPC" button
$buttonEnableReg.add_Click({Enable-RPC})
#End Custom Additions

$grpLocalComp.Controls.Add($buttonEnableReg)

$labelLocalCompReq.DataBindings.DefaultDataSourceUpdateMode = 0

$System_Drawing_Point = New-Object System.Drawing.Point
$System_Drawing_Point.X = 7
$System_Drawing_Point.Y = 65
$labelLocalCompReq.Location = $System_Drawing_Point
$labelLocalCompReq.Name = "labelLocalCompReq"
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 44
$System_Drawing_Size.Width = 364
$labelLocalCompReq.Size = $System_Drawing_Size
$labelLocalCompReq.TabIndex = 1
$labelLocalCompReq.Text = "Prerequisites:  You must be a member of the computers local Administrators Group to perform this action."

$grpLocalComp.Controls.Add($labelLocalCompReq)

$labelLocalComp.DataBindings.DefaultDataSourceUpdateMode = 0

$System_Drawing_Point = New-Object System.Drawing.Point
$System_Drawing_Point.X = 7
$System_Drawing_Point.Y = 20
$labelLocalComp.Location = $System_Drawing_Point
$labelLocalComp.Name = "labelLocalComp"
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 41
$System_Drawing_Size.Width = 364
$labelLocalComp.Size = $System_Drawing_Size
$labelLocalComp.TabIndex = 0
$labelLocalComp.Text = "A key will be enabled in the registry that allows Remote Procedure Calls to be made to this computer."

$grpLocalComp.Controls.Add($labelLocalComp)


$labelRegNote.DataBindings.DefaultDataSourceUpdateMode = 0

$System_Drawing_Point = New-Object System.Drawing.Point
$System_Drawing_Point.X = 7
$System_Drawing_Point.Y = 7
$labelRegNote.Location = $System_Drawing_Point
$labelRegNote.Name = "labelRegNote"
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 71
$System_Drawing_Size.Width = 377
$labelRegNote.Size = $System_Drawing_Size
$labelRegNote.TabIndex = 1
$labelRegNote.Text = "By default, the AllowRPC registry key is not enabled in Windows and computers will not receive your messages.  This form can be used to either create a GPO that enables the required key if you are using Active Directory or enable the key directly by running the program on each computer locally."

$OptTab.Controls.Add($labelRegNote)

$grpPolicy.Anchor = 13

$grpPolicy.DataBindings.DefaultDataSourceUpdateMode = 0
$System_Drawing_Point = New-Object System.Drawing.Point
$System_Drawing_Point.X = 7
$System_Drawing_Point.Y = 81
$grpPolicy.Location = $System_Drawing_Point
$grpPolicy.Name = "grpPolicy"
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 221
$System_Drawing_Size.Width = 377
$grpPolicy.Size = $System_Drawing_Size
$grpPolicy.TabIndex = 0
$grpPolicy.TabStop = $False
$grpPolicy.Text = "Group Policy"

$OptTab.Controls.Add($grpPolicy)

$buttonCreateGPO.DataBindings.DefaultDataSourceUpdateMode = 0

$System_Drawing_Point = New-Object System.Drawing.Point
$System_Drawing_Point.X = 7
$System_Drawing_Point.Y = 188
$buttonCreateGPO.Location = $System_Drawing_Point
$buttonCreateGPO.Name = "buttonCreateGPO"
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 23
$System_Drawing_Size.Width = 75
$buttonCreateGPO.Size = $System_Drawing_Size
$buttonCreateGPO.TabIndex = 2
$buttonCreateGPO.Text = "Create GPO"
$buttonCreateGPO.UseVisualStyleBackColor = $True

#Custom Addition
#Handles the "Create GPO" button
$buttonCreateGPO.add_Click({Create-RPCGPO $buttonCreateGPO})

#Disabled if no Active Directory
$buttonCreateGPO.Enabled = Test-ADExists
#End Custom Addition

$grpPolicy.Controls.Add($buttonCreateGPO)

$labelPolicyReq.DataBindings.DefaultDataSourceUpdateMode = 0

$System_Drawing_Point = New-Object System.Drawing.Point
$System_Drawing_Point.X = 7
$System_Drawing_Point.Y = 106
$labelPolicyReq.Location = $System_Drawing_Point
$labelPolicyReq.Name = "labelPolicyReq"
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 79
$System_Drawing_Size.Width = 364
$labelPolicyReq.Size = $System_Drawing_Size
$labelPolicyReq.TabIndex = 1
$labelPolicyReq.Text = "Prerequisites:  You must be a member of the Administrators or Group Policy Creator Owners groups and running this program on either a Windows Server 2008 R2 Domain Controller, a Windows Server 2008 member server with the GPMC installed, or Windows 7 with Remote Server Administration Tools (RSAT) installed."

$grpPolicy.Controls.Add($labelPolicyReq)

$labelPolicy.DataBindings.DefaultDataSourceUpdateMode = 0

$System_Drawing_Point = New-Object System.Drawing.Point
$System_Drawing_Point.X = 7
$System_Drawing_Point.Y = 20
$labelPolicy.Location = $System_Drawing_Point
$labelPolicy.Name = "labelPolicy"
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 86
$System_Drawing_Size.Width = 364
$labelPolicy.Size = $System_Drawing_Size
$labelPolicy.TabIndex = 0
$labelPolicy.Text = "A new Group Policy object will be created and linked to the root of your domain, and no existing GPOs will be changed.  The created policy is applied normally at boot time, so you may run ''gpupdate /force'' from a command prompt on each member computer if you wish to apply the policy immediately."

$grpPolicy.Controls.Add($labelPolicy)



#Custom Additions

#Settings for the Open File Dialog when opening a text file
$openFileDialog1.InitialDirectory = "$env:userprofile\Documents"
$openFileDialog1.Filter = "Text Files (*.txt) | *.txt"
$openFileDialog1.ShowHelp = $True
#End Custom Addition

#endregion Generated Form Code

#Save the initial state of the form
$InitialFormWindowState = $form1.WindowState
#Init the OnLoad event to correct the initial state of the form
$form1.add_Load($OnLoadForm_StateCorrection)

#Display correctly outside of ISE
[System.Windows.Forms.Application]::EnableVisualStyles()

#Show the Form
$form1.ShowDialog()| Out-Null

#If yes, the script is restarted prompting for admin credentials.
if ($runAdmin -eq "Yes") {
    Start-Process -FilePath PowerShell.exe -Verb RunAs -ArgumentList "-NonInteractive", "-WindowStyle Hidden", "-File $PSCommandPath"
}