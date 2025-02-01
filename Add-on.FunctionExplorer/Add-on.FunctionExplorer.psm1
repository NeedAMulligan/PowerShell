Set-StrictMode -Version 2

#region Internals
if (-not ('PowerShellTypeExtensions.Win32Window' -as [System.Type]))
	{ $cSharpCode = @'
		using System;

		namespace PowerShellTypeExtensions
		{
			public class Win32Window : System.Windows.Forms.IWin32Window
			{
				public static Win32Window CurrentWindow
				{
					get { return new Win32Window(System.Diagnostics.Process.GetCurrentProcess().MainWindowHandle); }
				}

				public Win32Window(IntPtr handle)
				{
					_hwnd = handle;
				}

				public IntPtr Handle {
					get { return _hwnd;	}
				}

				private IntPtr _hwnd;
			}
		}
'@

Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition $cSharpCode
}

#region Get-Type
function Get-Type
{
	param(
    	[Parameter(Position=0,Mandatory=$true)]
		[string] $GenericType,
		
		[Parameter(Position=1,Mandatory=$true)]
		[string[]] $T
    )

	$T = $T -as [type[]]
	
	try
	{
		$generic = [type]($GenericType + '`' + $T.Count)
		$generic.MakeGenericType($T)
	}
	catch [Exception]
	{
		throw New-Object System.Exception("Cannot create generic type", $_.Exception)
	}
}
#endregion

#region Invoke-Ternary
function Invoke-Ternary ([scriptblock]$decider, [scriptblock]$ifTrue, [scriptblock]$ifFalse) 
{
	if (&$decider)
	{ 
		&$ifTrue
	}
	else
	{
		&$ifFalse
	}
}
Set-Alias ?? Invoke-Ternary -Option AllScope -Description "Ternary Operator like '?' in C#" -Scope Global
#endregion
#endregion

#region Initialize the Script Editor Add-on.

$minimumPowerGUIVersion = [System.Version]'2.4.0.1659'

if ($Host.Name –ne 'PowerGUIScriptEditorHost') {
	return
}

if ($Host.Version -lt $minimumPowerGUIVersion) {
	[System.Windows.Forms.MessageBox]::Show([PowerShellTypeExtensions.Win32Window]::CurrentWindow,"The ""$(Split-Path -Path $PSScriptRoot -Leaf)"" Add-on module requires version $minimumPowerGUIVersion or later of the Script Editor. The current Script Editor version is $($Host.Version).$([System.Environment]::NewLine * 2)Please upgrade to version $minimumPowerGUIVersion and try again.","Version $minimumPowerGUIVersion or later is required",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
	return
}

$pgse = [Quest.PowerGUI.SDK.ScriptEditorFactory]::CurrentInstance

#endregion

#region Get-FEFunctions
function Get-FEFunctions
{
	param(
		[Parameter(Mandatory=$false,Position=0)]
		[ValidateNotNullOrEmpty()]
		[string] $DocumentTitle
	)
	
	#Write-Host "Get-FEFunctions called, Document Title is :" $DocumentTitle
	foreach ($document in $PGSE.DocumentWindows)
	{
		if ($DocumentTitle)
		{
			if ($document.Title -ne $DocumentTitle)
			{
				#Write-Host "Skipping document:" $document.Title
				continue
			}
			
			if($global:functionExplorer_documents.Item($document).LineCount -eq $document.Document.Lines.Count)
			{
				#Write-Host "Current LineCount of $($document.Title):" $document.Document.Lines.Count
				#Write-Host "Saved LineCount of $($document.Title):" $global:functionExplorer_documents.Item($document.Title).LineCount
				#Write-Host "Skipping, line count not changed:" $document.Title
				continue
			}
			
			#Write-Host "Removing functions"
			#Write-Host "	Prev :" $global:functionExplorer_documents.FunctionCount
			[Void]$global:functionExplorer_documents.Remove($DocumentTitle)
			#Write-Host "	After:" $global:functionExplorer_documents.FunctionCount
		}
		
		$feDocument = New-Object FunctionExplorer.Document($document.Title, $document.Document.Lines.Count)
		
		$lineNumber = 0
		#Write-Host "Searching for functions in document" $document.Title
		foreach ($line in $document.Document.Lines)
		{
			#Write-Host '.' -NoNewline
			try
			{
				$lineNumber++
				$f = [System.Text.RegularExpressions.Regex]::Matches(
					$line,
					'((^\s+)|(^))(((F|f)unction ))[0-9A-Za-z-_]+')
				if ($f.Count)
				{
					$functionName = $f[0].Value.Substring($f[0].Value.IndexOf(" ") + 1)
					$function = New-Object FunctionExplorer.Function($document.Title, $functionName, $lineNumber)
					$feDocument.Functions.Add($function)
				}
			}
			catch [Exception]
			{
				Write-Host "Error" $_.Exception
			}
		}
		$global:functionExplorer_documents.Add($feDocument)
		#Write-Host
		#Write-Host "Known functions:" $global:functionExplorer_documents.FunctionCount
	}
}
#endregion

#region Update-FEData
function Update-FEData
{
	$PGSE = [Quest.PowerGUI.SDK.ScriptEditorFactory]::CurrentInstance
	#Write-Host "PowerGui Document Count:" $PGSE.DocumentWindows.Count
	#Write-Host "FunctionExplorer Document Count:" $global:functionExplorer_documents.DocumentCount
	
	if ($PGSE.DocumentWindows.Count -ne $global:functionExplorer_documents.DocumentCount)
	{
		#Write-Host "Document Count has changed" ($PGSE.DocumentWindows.Count - $global:functionExplorer_documents.DocumentCount)
		
		#get list of all open document titles
		$documentTitles = foreach ($document in $PGSE.DocumentWindows)
		{
			$document.Title
		}
		#Write-Host "Open documents:" ($documentTitles -join " ")
		$global:functionExplorer_documents.Remove($global:functionExplorer_documents.GetOrphanedDocuments($documentTitles))
		$global:functionExplorer_documents.AddRange($global:functionExplorer_documents.GetNewDocuments($documentTitles))
	}
	
	Get-FEFunctions -DocumentTitle $PGSE.CurrentDocumentWindow.Title
	Add-FENodes -DocumentTitle $PGSE.CurrentDocumentWindow.Title
	
	foreach ($node in $trvFunctions.Nodes)
	{
		$node.Collapse()
	}
	$trvFunctions.Nodes.Item($PGSE.CurrentDocumentWindow.Title).Expand()
}
#endregion

#region Add-FENodes
function Add-FENodes
{
	param(
		[Parameter(Mandatory=$false,Position=0)]
		[ValidateNotNullOrEmpty()]
		[string] $DocumentTitle
	)
	#Write-Host "calling Add-FENodes"
	[FunctionExplorer.TreeNodeFactory]::UpdateTreeNodes($trvFunctions, $functionExplorer_documents)	
}
#endregion

#region handler_trvFunctions_MouseDoubleClick 
$handler_trvFunctions_MouseDoubleClick = 
{
	#Write-Host "handler_trvFunctions_MouseDoubleClick called"
	#Write-Host "Selected node tag:" $trvFunctions.SelectedNode.Tag
	$activeDocument = foreach ($document in $PGSE.DocumentWindows)
	{
		if ($document.Title -eq $trvFunctions.SelectedNode.Tag.Split(';')[1])
		{ $document	}
	}
	
	$oldtag = ''	
	if ($activeDocument)
	{
		#write-host "Tag before Activation" $trvFunctions.SelectedNode.Tag
		$oldtag = $trvFunctions.SelectedNode.Tag
		$activeDocument.Activate()
		#write-host "Tag after Activation" $trvFunctions.SelectedNode.Tag
		#write-host "Doc activated"
	}
	else
	{
		#assume the document has been closed
		if ($trvFunctions.SelectedNode.Tag.StartsWith('d'))
		{
			$trvFunctions.Nodes.Remove($trvFunctions.SelectedNode)
		}
		elseif ($trvFunctions.SelectedNode.Tag.StartsWith('f'))
		{
			$trvFunctions.Nodes.Remove($trvFunctions.SelectedNode.Parent)
		}
		return
	}
	
	#write-host "Tag" $trvFunctions.SelectedNode.Tag "starts with f?"
	if ($trvFunctions.SelectedNode.Tag.StartsWith("f"))
	{
		#write-host "Now jumping to line" $trvFunctions.SelectedNode.Tag.Split(';')[2]
		$scriptlines = ($script:pgse.CurrentDocumentWindow.Document.lines).count
		$script:pgse.CurrentDocumentWindow.Document.Set_Caretline(($scriptlines))
		$lineNumber = $trvFunctions.SelectedNode.Tag.Split(';')[2]
		$PGSE.CurrentDocumentWindow.Document.CaretLine = $lineNumber
		#$global:line = $PGSE.CurrentDocumentWindow.Document.Lines.Item($PGSE.CurrentDocumentWindow.Document.CaretLine)
		$PGSE.Commands.Item('EditCommand.ExpandOutlining').Invoke()
	}
	elseif($oldtag.length -gt 0)
	{
	
		#write-host "Now jumping to line" $oldTag.Split(';')[2]
		$scriptlines = ($script:pgse.CurrentDocumentWindow.Document.lines).count
		$script:pgse.CurrentDocumentWindow.Document.Set_Caretline(($scriptlines))	
		$script:pgse.CurrentDocumentWindow.Document.Set_Caretline(($oldTag.Split(';')[2]))
	}
}
#endregion

#region handler_trvFunctions_CurrentDocumentWindowChanged 
$handler_CurrentDocumentWindowChanged = 
{
	#Write-Host "handler_trvFunctions_CurrentDocumentWindowChanged called"
	Update-FEData
}
#endregion

#region handler_tsbRefreshTreeview_Click
$handler_tsbRefreshTreeview_Click = 
{	
	#Write-Host "handler_tsbRefreshTreeview_Click called"
	$functionExplorer_documents.Clear()
	$trvFunctions.Nodes.Clear()
	Get-FEFunctions
	Add-FENodes
	$trvFunctions.Nodes.Item($PGSE.CurrentDocumentWindow.Title).Expand()
}
#endregion

#region handler_tsbClearFilter_Click
$handler_tsbClearFilter_Click = 
{	
	#Write-Host "$handler_tsbClearFilter_Click called"
	$txtFunctionFilter.Text = [string]::Empty
}
#endregion

$PGSE = [Quest.PowerGUI.SDK.ScriptEditorFactory]::CurrentInstance
$global:functionExplorer_documents = New-Object FunctionExplorer.DocumentCollection

if (-not ($PGFunctionExplorer = $pgse.ToolWindows['FunctionExplorer']))
{
	$PGFunctionExplorer = $pgse.ToolWindows.Add('FunctionExplorer')
}
$PGFunctionExplorer.Title = 'Function Explorer'

#region UI
#region Define ImageList $imageList
$imageList = New-Object System.Windows.Forms.ImageList
$imageList.ImageSize = New-Object System.Drawing.Size(16, 16)
$imageList.Images.Add("Document", [System.Drawing.Image]::FromFile("$PSScriptRoot\Resources\Document.ico"))
$imageList.Images.Add("Function", [System.Drawing.Image]::FromFile("$PSScriptRoot\Resources\Function.ico"))
$imageList.Images.Add("GoToDefinition", [System.Drawing.Image]::FromFile("$PSScriptRoot\Resources\GoToDefinition.ico"))
$imageList.Images.Add("Refresh", [System.Drawing.Image]::FromFile("$PSScriptRoot\Resources\Refresh.ico"))
$imageList.Images.Add("RedX", [System.Drawing.Image]::FromFile("$PSScriptRoot\Resources\redx.ico"))
#endregion

#region Define Panel $pnlFunctionExplorer
$pnlFunctionExplorer = New-Object System.Windows.Forms.Panel
$pnlFunctionExplorer.AutoSize = $True
$pnlFunctionExplorer.AutoSizeMode = 'GrowAndShrink'
$pnlFunctionExplorer.Dock = 'Fill'
$pnlFunctionExplorer.Location = '0, 0'
$pnlFunctionExplorer.Name = "pnlFunctionExplorer"
$pnlFunctionExplorer.Size = '709, 477'
$pnlFunctionExplorer.TabIndex = 0
#endregion

#region Define ToolStrip tstTop and ToolStrip items
$tstTop = New-Object System.Windows.Forms.ToolStrip
$tstTop.TabIndex = 1
$tstTop.Location = '0, 0'
$tstTop.Size.Height = 32

$labFunctionFilter = New-Object System.Windows.Forms.ToolStripLabel
$labFunctionFilter.Text = "Filter:"
$labFunctionFilter.Size = '33, 22'

$tsbRefreshTreeview = New-Object System.Windows.Forms.ToolStripButton
$tsbRefreshTreeview.DisplayStyle = "Image"
$tsbRefreshTreeview.ToolTipText = "Refreshed the function treeview"
$tsbRefreshTreeview.Image = $imageList.Images.Item("Refresh")

$txtFunctionFilter = New-Object System.Windows.Forms.ToolStripTextBox
$txtFunctionFilter.Size = '100, 25'

$tsbClearFilter = New-Object System.Windows.Forms.ToolStripButton
$tsbClearFilter.DisplayStyle = "Image"
$tsbClearFilter.ToolTipText = "Clear the Filter"
$tsbClearFilter.Image = $imageList.Images.Item("redx")
#endregion

#region Define TreeView $trvFunctions
$trvFunctions = New-Object System.Windows.Forms.TreeView
$trvFunctions.ImageList = $imageList
$trvFunctions.Anchor = 'Top, Bottom, Left, Right'
$trvFunctions.Location = '10, 32'
$trvFunctions.Size = '685, 423'
$trvFunctions.TabIndex = 1
#endregion

#region Add UI Elements to Tool Windows
$tstTop.Items.Add($tsbRefreshTreeview)
$tstTop.Items.Add($labFunctionFilter)
$tstTop.Items.Add($txtFunctionFilter)
$tstTop.Items.Add($tsbClearFilter)

$pnlFunctionExplorer.Controls.Add($tstTop)
$pnlFunctionExplorer.Controls.Add($trvFunctions)

$PGFunctionExplorer.Control = $pnlFunctionExplorer
$PGFunctionExplorer.Visible = $true
#endregion
#endregion

$trvFunctions.add_MouseDoubleClick($handler_trvFunctions_MouseDoubleClick)
$PGSE.add_CurrentDocumentWindowChanged($handler_CurrentDocumentWindowChanged)
$tsbRefreshTreeview.add_Click($handler_tsbRefreshTreeview_Click)
$tsbClearFilter.add_Click($handler_tsbClearFilter_Click)
#$txtFunctionFilter

$PGFunctionExplorer.Control.Invoke([EventHandler]{$PGFunctionExplorer.Control.Parent.Activate($true)})
$PGSE.Commands.Item("EditCommand.ExpandOutlining").AddShortcut([Windows.Forms.Keys]::Control -bor [Windows.Forms.Keys]::Add)
$PGSE.Commands.Item("EditCommand.CollapseOutlining").AddShortcut([Windows.Forms.Keys]::Control -bor [Windows.Forms.Keys]::Subtract)

Get-FEFunctions
Add-FENodes

#expand node for current document
try { $trvFunctions.Nodes.Item($PGSE.CurrentDocumentWindow.Title).Expand() } catch { }

#region Add a menu option for FunctionExplorer in the in the Go menu
$FunctionExplorerCommand = New-Object -TypeName Quest.PowerGUI.SDK.ItemCommand('GoCommand','FunctionExplorer')
$FunctionExplorerCommand.Text = 'FunctionExplorer'
$FunctionExplorerCommand.Image = $imageList.Images.Item('GoToDefinition')
$FunctionExplorerCommand.AddShortcut('Ctrl+4')
$FunctionExplorerCommand.ScriptBlock = {
	if ($PGFunctionExplorer = $pgse.ToolWindows['FunctionExplorer']) {
		$PGFunctionExplorer.Visible = $true
		$PGFunctionExplorer.Control.Invoke([EventHandler]{$PGFunctionExplorer.Control.Parent.Activate($true)})
	}
}
$PGSE.Commands.Add($FunctionExplorerCommand)

if (($viewMenu = $pgse.Menus['MenuBar.Go']) -and (-not ($clearConsoleMenuItem = $viewMenu.Items['GoCommand.FunctionExplorer'])))
{
	$viewMenu.Items.Add($FunctionExplorerCommand)
	if ($clearConsoleMenuItem = $viewMenu.Items['GoCommand.FunctionExplorer'])
	{
		$clearConsoleMenuItem.FirstInGroup = $true
	}
}
#endregion

#region Add a menu option for 'Go to Definition'
$GoToDefinitionCommand = New-Object -TypeName Quest.PowerGUI.SDK.ItemCommand('EditCommand','GoToDefinition')
$GoToDefinitionCommand.Text = 'Go to Definition'
$GoToDefinitionCommand.Image = $imageList.Images.Item('GoToDefinition')
$GoToDefinitionCommand.AddShortcut('F12')
$GoToDefinitionCommand.ScriptBlock = {
	$line = $PGSE.CurrentDocumentWindow.Document.Lines.Item($PGSE.CurrentDocumentWindow.Document.CaretLine)
	$linePosition = $PGSE.CurrentDocumentWindow.Document.CaretCharacter
	$matches = [regex]::Matches($line, "[\w-]+")
	$functionName = [string]::Empty

	foreach ($m in $matches)
	{
		if ($m.Index -gt $linePosition)
		{ break	}
		else
		{ $functionName = $m.Value }
	}
	
	try
	{
		$f = $functionExplorer_documents.GetFunctionByName($functionName, $PGSE.CurrentDocumentWindow.Title)
		
		$activeDocument = foreach ($document in $PGSE.DocumentWindows) { if ($document.Title  -eq $f.DocumentTitle) { $document } }
		$activeDocument.Activate()
		$PGSE.CurrentDocumentWindow.Document.CaretLine = $f.LineNumber
		$PGSE.Commands.Item('EditCommand.ExpandOutlining').Invoke()
	}
	catch { }
}
$PGSE.Commands.Add($GoToDefinitionCommand)
($PGSE.Toolbars | Where-Object { $_.Title -eq 'Text Editor' }).Items.Add($GoToDefinitionCommand)

if (($viewMenu = $pgse.Menus['MenuBar.Edit']) -and (-not ($clearConsoleMenuItem = $viewMenu.Items['EditCommand.GoToDefinition'])))
{
	$viewMenu.Items.Add($GoToDefinitionCommand)
	if ($clearConsoleMenuItem = $viewMenu.Items['EditCommand.GoToDefinition'])
	{
		$clearConsoleMenuItem.FirstInGroup = $true
	}
}
#endregion