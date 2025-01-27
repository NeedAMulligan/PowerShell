# Zip file location
$ArchiveLocation = "c:\windows\ltsvc\packages\chiptone\chiptone-win.zip" 

# Which directory to extract to
$ExtractToPath = "c:\chiptone-win"

# If the directory specified for extraction doesn't exist, create it.
new-item -ItemType Directory -Path $ExtractToPath -ea SilentlyContinue | out-null

if (-not (Test-Path $ExtractToPath))
{
	Write-Output "Failed to create temporary directory used for storing extracted files!"
	return;
}

$Result = Expand-Archive $ArchiveLocation $ExtractToPath

if ($Result -eq $true)
{
	Write-Output "Files extracted successfully!"
}
else
{
	Write-Output "Files failed to extract!"
}

# Creates desktop shortcut and sets icon
$Shell = New-Object -ComObject ("WScript.Shell")
$Shortcut = $Shell.CreateShortcut('C:\users\public\desktop\ChipTone.lnk')
$Shortcut.TargetPath = "C:\chiptone-win\ChipTone.exe"
$ShortCut.WindowStyle = 3;
$Shortcut.IconLocation = $ShortCut.IconLocation = 'c:\chiptone-win\icon.ico'
$Shortcut.WorkingDirectory = "C:\chiptone-win\"
$ShortCut.Description = 'ChipTone'
$ShortCut.Save()

# Delete zip archive
Remove-item C:\chiptone-win.zip