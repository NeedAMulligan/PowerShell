<#
.SYNOPSIS
    A robust local utility to create ISO 9660/UDF image files from local folders or files.

.DESCRIPTION
    This script provides an interactive interface to package local data into an ISO file. 
    It utilizes the IMAPI2 COM interfaces for high-performance image creation and 
    includes comprehensive error handling, logging, and pre-flight system checks.

.PARAMETER SourcePath
    The local directory or file(s) to be included in the ISO.
.PARAMETER DestinationPath
    The full path where the .iso file will be saved.

.EXAMPLE
    .\New-LocalIsoCreator.ps1
    Runs the script in interactive mode, prompting for source and destination.

.NOTES
    Exit Codes:
    0 - Success
    1 - General Error / Catch Block Triggered
    2 - Missing Administrative Privileges
    3 - Insufficient Disk Space
    4 - Prerequisite Check Failed (IMAPI2 missing)
#>

# ---------------------------------------------------------------------------
# VARIABLES & CONFIGURATION
# ---------------------------------------------------------------------------
$Global:ScriptConfig = @{
    LogPath          = "C:\temp"
    DefaultIsoName   = "Archive_$(Get-Date -Format 'yyyyMMdd')"
    LogName          = "New-IsoFile_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    RequiredSpacePad = 100MB  # Extra buffer for ISO overhead
}

# ---------------------------------------------------------------------------
# LOGGING & UTILITY FUNCTIONS
# ---------------------------------------------------------------------------
function Write-Log {
    param([string]$Message, [ValidateSet('INFO', 'WARN', 'ERROR')]$Level = 'INFO')
    $Stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Stamp] [$Level] $Message"
    Write-Host $LogEntry -ForegroundColor (switch($Level){'WARN' {'Yellow'}; 'ERROR' {'Red'}; Default {'White'}})
    
    if (!(Test-Path $Global:ScriptConfig.LogPath)) { New-Item -Path $Global:ScriptConfig.LogPath -ItemType Directory -Force | Out-Null }
    $LogFile = Join-Path $Global:ScriptConfig.LogPath $Global:ScriptConfig.LogName
    $LogEntry | Out-File -FilePath $LogFile -Append
}

# Embedded C# Class for low-level Stream-to-File writing
if (!('ISOFile' -as [type])) {
    $cp = New-Object System.CodeDom.Compiler.CompilerParameters
    $cp.CompilerOptions = '/unsafe'
    Add-Type -CompilerParameters $cp -TypeDefinition @'
    using System;
    using System.IO;
    using System.Runtime.InteropServices.ComTypes;

    public class ISOFile {
        public unsafe static void Create(string Path, object Stream, int BlockSize, int TotalBlocks) {
            int bytes = 0;
            byte[] buf = new byte[BlockSize];
            var ptr = (IntPtr)(&bytes);
            using (var o = File.OpenWrite(Path)) {
                var i = Stream as IStream;
                if (i != null) {
                    while (TotalBlocks-- > 0) {
                        i.Read(buf, BlockSize, ptr);
                        o.Write(buf, 0, bytes);
                    }
                }
            }
        }
    }
'@
}

# ---------------------------------------------------------------------------
# PRE-FLIGHT CHECKS
# ---------------------------------------------------------------------------
function Invoke-PreflightChecks {
    Write-Log "Starting Pre-flight checks..."

    # 1. Check Admin Rights
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Log "Script must be run as Administrator." "ERROR"
        exit 2
    }

    # 2. Check for IMAPI2 COM Object
    try {
        $testImage = New-Object -ComObject IMAPI2FS.MsftFileSystemImage -ErrorAction Stop
        Write-Log "IMAPI2 COM components verified."
    } catch {
        Write-Log "IMAPI2 components not found. Ensure Windows Media features are enabled." "ERROR"
        exit 4
    }
}

# ---------------------------------------------------------------------------
# MAIN LOGIC
# ---------------------------------------------------------------------------
function Start-IsoCreation {
    try {
        # INTERACTIVE INPUT
        Write-Host "--- Local ISO Creator ---" -ForegroundColor Cyan
        $Source = Read-Host "Enter the full path of the FOLDER to turn into an ISO"
        if (!(Test-Path $Source)) { throw "Source path '$Source' does not exist." }

        $IsoName = Read-Host "Enter desired ISO filename (e.g., MyBackup.iso)"
        if ($IsoName -notlike "*.iso") { $IsoName += ".iso" }
        $TargetPath = Join-Path $Global:ScriptConfig.LogPath $IsoName

        # SPACE CHECK
        Write-Log "Calculating source size..."
        $SourceSize = (Get-ChildItem $Source -Recurse | Measure-Object -Property Length -Sum).Sum
        $FreeSpace = (Get-PSDrive C).Free
        
        if ($FreeSpace -lt ($SourceSize + $Global:ScriptConfig.RequiredSpacePad)) {
            Write-Log "Insufficient disk space on C:. Needed: $([Math]::Round($SourceSize/1GB,2))GB" "ERROR"
            exit 3
        }

        # ISO GENERATION
        Write-Log "Initializing Image Engine for: $IsoName"
        $Image = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
        $Image.VolumeName = [System.IO.Path]::GetFileNameWithoutExtension($IsoName)
        $Image.ChooseImageDefaultsForMediaType(13) # Default to 'DISK' / DVDPLUSRW_DUALLAYER equivalent

        Write-Log "Adding files to image tree (this may take a moment)..."
        $Image.Root.AddTree($Source, $true)

        Write-Log "Finalizing stream and writing to disk..."
        $Result = $Image.CreateResultImage()
        [ISOFile]::Create($TargetPath, $Result.ImageStream, $Result.BlockSize, $Result.TotalBlocks)

        Write-Log "SUCCESS: ISO created at $TargetPath" "INFO"
        
    } catch {
        Write-Log "CRITICAL ERROR: $($_.Exception.Message)" "ERROR"
        if (Test-Path $TargetPath) { 
            Write-Log "Cleaning up partial file..." "WARN"
            Remove-Item $TargetPath -Force 
        }
        exit 1
    }
}

# ---------------------------------------------------------------------------
# EXECUTION
# ---------------------------------------------------------------------------
Clear-Host
Invoke-PreflightChecks
Start-IsoCreation

Write-Host "`nPress any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
exit 0
